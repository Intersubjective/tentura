@Tags(['pg'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart' show Connection, Sql;
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/attention_system_settlement_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/attention_dispatch_port.dart';
import 'package:tentura_server/domain/port/forward_attribution_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/fake_user_block_repository.dart';
import '../../support/noop_commitment_query_case.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/user_erasure_test_stack.dart'
    show buildDefaultUserRepository;

const _author = 'Uxhandleauth01';
const _other = 'Uxhandleother1';
const _invitee = 'Uxhandleinvt01';
const _post = 'Bxhandlepost01';
const _draft = 'Bxhandledraft1';
const _childDraft = 'Bxhandlechld01';
const _openBeacon = 'Bxhandleopen01';
const _invitation = 'Ixhandleinv001';
const _edge = 'Fxhandleedge01';
const _closing = 'Bxhandleclose1';

const _stateSql = '''
SELECT pg_backend_pid() AS pid,
       txid_current()::text AS tx,
       coalesce(current_setting('tentura.mutating_user_id', true), '') AS actor
''';

typedef _State = ({int pid, String tx, String actor});

Future<_State> _state(TenturaDb db) async {
  final row = await db.customSelect(_stateSql).getSingle();
  return (
    pid: row.read<int>('pid'),
    tx: row.read<String>('tx'),
    actor: row.read<String>('actor'),
  );
}

/// Reproduces the routing defect fixed for sibling handles: a handle resolves
/// every statement outside its own transactions to the bare leased executor,
/// ignoring a savepoint another handle over the same pool holds open.
final class _StaleRoutingDb extends TenturaDb {
  _StaleRoutingDb(super.pool, this._shared) : super.scoped();

  final _BareExecutor _shared;
  static const Symbol _zoneKey = #DatabaseConnectionUser;

  @override
  // Deliberately reproduce the old routing behavior instead of Drift's guard.
  DatabaseConnectionUser get resolvedEngine {
    // Capture the outer leased user before another handle opens a savepoint.
    final fixed = super.resolvedEngine;
    final inZone = Zone.current[_zoneKey];
    if (inZone is! DatabaseConnectionUser) {
      _shared.bare = fixed;
      return fixed;
    }
    // Compare the attached owner just as Drift normally does in resolvedEngine.
    // ignore: invalid_use_of_visible_for_overriding_member
    if (identical(inZone.attachedDatabase, this)) return inZone;
    return _shared.bare ?? fixed;
  }
}

final class _BareExecutor {
  DatabaseConnectionUser? bare;
}

final class _Abort implements Exception {}

typedef _Handles = TenturaDb Function();

final class _Path {
  const _Path(this.name, this.actor, this.effectSql, this.run);

  final String name;
  final String actor;

  /// Single text column `v`, changed by a successful run of [run].
  final String effectSql;

  /// Composes real repositories and use cases, each over its own handle from
  /// the factory, as DI wires them.
  final Future<void> Function(_Handles handle) run;
}

class _NoopDispatch extends Fake implements AttentionDispatchPort {
  @override
  Future<void> record(AttentionDispatchIntent intent) async {}
}

class _FakeImageRepo extends Fake implements ImageRepositoryPort {}

class _FakeImageObjectGc extends Fake implements ImageObjectGcPort {}

class _FakeTaskRepo extends Fake implements TaskRepositoryPort {}

class _NoopForwardAttribution extends Fake
    implements ForwardAttributionRepositoryPort {}

class _AllVisiblePeers extends Fake implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}

Env get _testEnv => Env(environment: Environment.test);

TransactionalAttentionCase _attention(_Handles handle) =>
    TransactionalAttentionCase(
      MutatingUnitOfWork(handle()),
      _NoopDispatch(),
    );

BeaconCase _beaconCase(_Handles handle) => BeaconCase(
  BeaconRepository(handle()),
  _FakeImageRepo(),
  _FakeImageObjectGc(),
  _FakeTaskRepo(),
  noopCommitmentQueryCase(),
  FakeBeaconAccessGuard(),
  FakeBeaconHierarchyRepository(),
  FakeBeaconChildCreatePort(),
  buildLifecycleEffectsCase(),
  attention: _attention(handle),
  env: _testEnv,
  logger: Logger('CrossHandleMatrixBeaconCase'),
);

ForwardCase _forwardCase(_Handles handle) => ForwardCase(
  ForwardEdgeRepository(handle()),
  _NoopForwardAttribution(),
  HelpOfferRepository(handle()),
  InboxRepository(handle()),
  CapabilityEvidenceRepository(handle()),
  BeaconRepository(handle()),
  FakeUserBlockRepository(),
  _AllVisiblePeers(),
  FakeBeaconAccessGuard(),
  attention: _attention(handle),
  env: _testEnv,
  logger: Logger('CrossHandleMatrixForwardCase'),
);

ClosureFinalizeCase _finalizer(_Handles handle) => ClosureFinalizeCase(
  unitOfWork: MutatingUnitOfWork(handle()),
  closureRepository: ClosureRepository(handle()),
  beaconRepository: BeaconRepository(handle()),
  trustLedger: TrustLedgerRepository(handle()),
  lifecycleEffects: buildLifecycleEffectsCase(),
  attentionSystemSettlement: AttentionSystemSettlementRepository(handle()),
  trustPublisher: TrustPublisherCase(
    TrustPublishRepository(handle()),
    env: _testEnv,
    logger: Logger('CrossHandleMatrixPublisher'),
  ),
  env: _testEnv,
  logger: Logger('CrossHandleMatrixFinalizer'),
);

final _paths = <_Path>[
  _Path(
    'opening forwarding on a post',
    _author,
    "SELECT forward_policy::text AS v FROM public.beacon WHERE id = '$_post'",
    (handle) =>
        _beaconCase(handle).openForwarding(authorId: _author, id: _post),
  ),
  _Path(
    'publishing a draft request',
    _author,
    "SELECT status::text AS v FROM public.beacon WHERE id = '$_draft'",
    (handle) =>
        _beaconCase(handle).publishDraft(userId: _author, beaconId: _draft),
  ),
  _Path(
    'publishing a child draft request',
    _author,
    "SELECT status::text AS v FROM public.beacon WHERE id = '$_childDraft'",
    (handle) => BeaconRepository(
      handle(),
    ).publishChildDraft(childBeaconId: _childDraft, actorId: _author),
  ),
  _Path(
    'cancelling a forward before the recipient acts',
    _author,
    'SELECT (cancelled_at IS NOT NULL)::text AS v '
        "FROM public.beacon_forward_edge WHERE id = '$_edge'",
    (handle) async {
      final cancelled = await _forwardCase(
        handle,
      ).cancelForward(edgeId: _edge, senderId: _author);
      expect(cancelled, isTrue);
    },
  ),
  _Path(
    'marking an inbox item cancelled for a recipient',
    _other,
    'SELECT status::text AS v FROM public.inbox_item '
        "WHERE user_id = '$_other' AND beacon_id = '$_openBeacon'",
    (handle) => InboxRepository(handle()).markForwardCancelledForRecipient(
      beaconId: _openBeacon,
      recipientId: _other,
    ),
  ),
  _Path(
    'blocking a user',
    _author,
    'SELECT count(*)::text AS v FROM public.user_block',
    (handle) => UserBlockRepository(
      _testEnv,
      handle(),
    ).block(blockerId: _author, blockedId: _other, cascadeMode: 0),
  ),
  _Path(
    'accepting an invitation as an existing account',
    _invitee,
    "SELECT coalesce(invited_id, '') AS v FROM public.invitation "
        "WHERE id = '$_invitation'",
    (handle) => buildDefaultUserRepository(handle()).bindMutual(
      invitationId: _invitation,
      userId: _invitee,
      bindFriendship: false,
    ),
  ),
  _Path(
    'finalizing an expired closure epoch as the worker does',
    '',
    "SELECT status::text AS v FROM public.beacon WHERE id = '$_closing'",
    (handle) => ClosureFinalizeSweepCase(
      unitOfWork: MutatingUnitOfWork(handle()),
      closureRepository: ClosureRepository(handle()),
      finalizer: _finalizer(handle),
      env: _testEnv,
      logger: Logger('CrossHandleMatrixSweep'),
    ).run(),
  ),
];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CROSS_HANDLE_MATRIX_TEST_DB',
    defaultNamePrefix: 'tentura_test_cross_handle',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late MainDbPool pool;
  final created = <TenturaDb>[];

  Env envFor({required String environment, required bool debug}) {
    final db = target.databaseEnv;
    return Env(
      environment: environment,
      printEnv: false,
      isDebugModeOn: debug,
      serverUri: Uri.parse('http://localhost:2080'),
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      maxConnectionCount: 2,
    );
  }

  TenturaDb handle() {
    final db = TenturaDb.scoped(pool);
    created.add(db);
    return db;
  }

  Future<void> seed() async {
    await writer.execute('TRUNCATE public."user" CASCADE');
    var slot = 1;
    for (final id in [_author, _other, _invitee]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, now(), now())
'''),
        parameters: {'id': id, 'key': pgTestPublicKey('xhandle', slot++)},
      );
    }
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind,
  forward_policy, is_discoverable, published_at)
VALUES ('$_post', '$_author', '', '', 0, 1, 0, false, now())
''');
    for (final entry in {_draft: 3, _childDraft: 3, _openBeacon: 0}.entries) {
      await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  published_at)
VALUES ('${entry.key}', '$_author', 'Matrix request', '', ${entry.value},
  ${entry.value == 0 ? 'now()' : 'NULL'})
''');
    }
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('$_edge', '$_openBeacon', '$_author', '$_other')
''');
    await writer.execute('''
TRUNCATE public.beacon_closure, public.beacon_closure_member,
  public.beacon_closure_outcome, public.beacon_closure_result,
  public.beacon_closure_author_split, public.beacon_closure_support,
  public.beacon_closure_commit, public.beacon_closure_mark,
  public.beacon_closure_story, public.trust_evidence,
  public.trust_publish_queue CASCADE
''');
    await writer.execute(
      "UPDATE public.trust_cutover_state SET status = 'done' WHERE id = 1",
    );
    await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status,
  published_at)
VALUES ('$_closing', '$_author', 'Closing request', '',
  ${BeaconStatus.reviewOpen.smallintValue}, now())
''');
    await writer.execute('''
INSERT INTO public.beacon_closure (beacon_id, epoch, status, opened_at, closes_at)
VALUES ('$_closing', 1, 0, now() - interval '8 days',
  now() - interval '1 hour')
''');
    await writer.execute('''
INSERT INTO public.beacon_closure_member
  (beacon_id, epoch, user_id, departure, active_at_open)
VALUES ('$_closing', 1, '$_other', NULL, true)
''');
    await writer.execute('''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES ('$_closing', '$_other', 1)
''');
    await writer.execute('''
INSERT INTO public.inbox_item (user_id, beacon_id, status)
VALUES ('$_other', '$_openBeacon', 0)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = 0
''');
    await writer.execute('''
INSERT INTO public.invitation (id, user_id) VALUES ('$_invitation', '$_author')
''');
  }

  Future<String> committedEffect(_Path path) async =>
      (await writer.execute(path.effectSql)).first.first! as String;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
  });
  setUp(() async {
    pool = MainDbPool(
      envFor(environment: Environment.test, debug: false),
    );
    await seed();
  });
  tearDown(() async {
    for (final db in created) {
      await db.close().timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    created.clear();
    await pool.close().timeout(const Duration(seconds: 3), onTimeout: () {});
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  group('real repositories over separate handles of one pool', () {
    for (final path in _paths) {
      group(path.name, () {
        test(
          'every handle sees one backend, one transaction and the actor, and '
          'the change commits',
          () async {
            final outer = handle();
            final inner = handle();
            final before = await committedEffect(path);
            final states = <_State>[];
            await MutatingUnitOfWork(outer).run<void>(
              actorUserId: path.actor,
              action: () async {
                states.add(await _state(outer));
                await path.run(handle);
                states
                  ..add(await _state(inner))
                  ..add(await _state(outer));
              },
            );
            expect(states.toSet(), hasLength(1));
            expect(states.first.actor, path.actor);
            expect(await committedEffect(path), isNot(before));
          },
          timeout: const Timeout(Duration(seconds: 20)),
        );

        test(
          'a failed nested savepoint rolls back only its own change and keeps '
          'the transaction and actor',
          () async {
            final outer = handle();
            final inner = handle();
            final before = await committedEffect(path);
            final states = <_State>[];
            String? seenAfterRollback;
            await MutatingUnitOfWork(outer).run<void>(
              actorUserId: path.actor,
              action: () async {
                states.add(await _state(outer));
                await expectLater(
                  inner.transaction<void>(() async {
                    await path.run(handle);
                    states.add(await _state(inner));
                    throw _Abort();
                  }),
                  throwsA(isA<_Abort>()),
                );
                states
                  ..add(await _state(inner))
                  ..add(await _state(outer));
                seenAfterRollback =
                    (await outer.customSelect(path.effectSql).getSingle())
                        .read<String>('v');
              },
            );
            expect(states.toSet(), hasLength(1));
            expect(states.first.actor, path.actor);
            expect(seenAfterRollback, before);
            expect(await committedEffect(path), before);
          },
          timeout: const Timeout(Duration(seconds: 20)),
        );

        test(
          'an outer failure rolls the change back and the next unit of work '
          'starts a new transaction with no actor left behind',
          () async {
            final outer = handle();
            final before = await committedEffect(path);
            _State? during;
            await expectLater(
              MutatingUnitOfWork(outer).run<void>(
                actorUserId: path.actor,
                action: () async {
                  await path.run(handle);
                  during = await _state(outer);
                  throw _Abort();
                },
              ),
              throwsA(isA<_Abort>()),
            );
            expect(during!.actor, path.actor);
            expect(await committedEffect(path), before);
            final after = await _state(handle());
            expect(after.actor, isEmpty);
            expect(after.tx, isNot(during!.tx));
          },
          timeout: const Timeout(Duration(seconds: 20)),
        );

        test(
          'the whole composition holds exactly one pool admission slot',
          () async {
            final outer = handle();
            var running = -1;
            await MutatingUnitOfWork(outer).run<void>(
              actorUserId: path.actor,
              action: () async {
                await path.run(handle);
                running = pool.admission.running;
              },
            );
            expect(running, 1);
            expect(pool.admission.running, 0);
          },
          timeout: const Timeout(Duration(seconds: 20)),
        );

        test(
          'with debug off in a test environment, a statement sent to the outer '
          'executor while a sibling holds the innermost transaction fails with '
          'a diagnostic naming both executors',
          () async {
            final shared = _BareExecutor();
            _StaleRoutingDb stale() {
              final db = _StaleRoutingDb(pool, shared);
              created.add(db);
              return db;
            }

            final outer = stale();
            final sibling = stale();
            await expectLater(
              MutatingUnitOfWork(outer)
                  .run<void>(
                    actorUserId: path.actor,
                    action: () => sibling.transaction(() async {
                      await path.run(stale);
                      // The outer handle still resolves to the bare leased
                      // executor, which the sibling's savepoint has locked.
                      await outer.customSelect('SELECT 1').get();
                    }),
                  )
                  .timeout(const Duration(seconds: 8)),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('innermost'),
                    contains('expected'),
                    contains('actual'),
                  ),
                ),
              ),
            );
          },
          timeout: const Timeout(Duration(seconds: 25)),
        );
      });
    }
  });

  group('actor and isolation checks across handles', () {
    test(
      'a nested mutation by another actor on a sibling handle is refused',
      () async {
        final outer = handle();
        final inner = handle();
        await expectLater(
          MutatingUnitOfWork(outer).run<void>(
            actorUserId: _author,
            action: () => inner.withMutatingUser(_other, () async {}),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('actor mismatch'),
            ),
          ),
        );
      },
    );

    test(
      'repeatable read cannot be entered on a sibling handle inside a read '
      'committed mutation',
      () async {
        final outer = handle();
        final inner = handle();
        await expectLater(
          MutatingUnitOfWork(outer).run<void>(
            actorUserId: _author,
            action: () =>
                inner.withMutatingRepeatableRead<void>(_author, () async {}),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('repeatable read'),
            ),
          ),
        );
      },
    );

    test(
      'a read snapshot inside a plain transaction on a sibling handle is '
      'refused by a guard before any SET TRANSACTION is sent',
      () async {
        final outer = handle();
        final inner = handle();
        Object? failure;
        try {
          await outer.withTransaction(
            () => inner.withReadSnapshot(() async {}),
          );
        } on Object catch (error) {
          failure = error;
        }
        expect(failure, isA<StateError>());
        expect(failure, isNot(isA<ServerException>()));
        expect(
          (failure! as StateError).message,
          allOf(contains('isolation'), contains('read snapshot')),
        );
      },
    );
  });

  group('closed scope guard', () {
    test('an executor reference kept past its scope fails with a closed-scope '
        'diagnostic', () async {
      final db = handle();
      late DatabaseConnectionUser escaped;
      await db.withConnectionScope(() async {
        // Keep the leased user itself so access after closure exercises its guard.
        escaped = db.resolvedEngine;
        await escaped.customSelect('SELECT 1').get();
      });
      await expectLater(
        escaped.customSelect('SELECT 1').get(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('closed'), contains('scope')),
          ),
        ),
      );
    });

    test(
      'work scheduled inside a scope that runs after it closed is refused',
      () async {
        final db = handle();
        late Future<void> late_;
        await db.withConnectionScope(() async {
          late_ = Future<void>.delayed(
            const Duration(milliseconds: 50),
            () => db.customSelect('SELECT 1').get(),
          )..ignore();
        });
        await expectLater(
          late_,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('closed'),
            ),
          ),
        );
      },
    );
  });

  group('guards by environment', () {
    test(
      'a production environment does not enforce the admission guard',
      () async {
        final prodPool = MainDbPool(
          envFor(environment: Environment.prod, debug: false),
        );
        final db = TenturaDb.scoped(prodPool);
        created.add(db);
        try {
          await db.withConnectionScope(() async {
            expect(await prodPool.admission.run(() async => 1), 1);
          });
        } finally {
          await prodPool.close().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          );
        }
      },
    );

    test('a debug environment enforces the admission guard', () async {
      final debugPool = MainDbPool(
        envFor(environment: Environment.dev, debug: true),
      );
      final db = TenturaDb.scoped(debugPool);
      created.add(db);
      try {
        await db.withConnectionScope(() async {
          await expectLater(
            debugPool.admission.run(() async => 1),
            throwsA(isA<StateError>()),
          );
        });
      } finally {
        await debugPool.close().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      }
    });

    test('a test environment enforces the admission guard even with debug '
        'off', () async {
      final db = handle();
      await db.withConnectionScope(() async {
        await expectLater(
          pool.admission.run(() async => 1),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
