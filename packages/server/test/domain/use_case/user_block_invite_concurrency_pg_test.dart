@Tags(['pg', 'multi-connection'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/author_invite_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/invite_genealogy_repository.dart';
import 'package:tentura_server/data/repository/invite_seed_prompt_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/user_block/user_block_withdraw_reason.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/pg_wait.dart';

const _missingUser = 'Unotpresent0';
const _contactWriteGate = 719402;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_BLOCK_INVITE_TEST_DB',
    defaultNamePrefix: 'tentura_test_block_invite',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  final recorder = _BlockStatements();
  late Connection writer;
  late Connection gate;
  late Env env;
  late UserBlockCase recordedBlocks;
  late UserBlockCase blocks;
  late InvitationCase invites;
  var nextPair = 0;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    addTearDown(() => tearDownDisposablePgWriter(session: session));
    writer = session.writer;
    final db = target.databaseEnv;
    gate = await Connection.open(
      db.pgEndpoint,
      settings: db.pgEndpointSettings,
    );
    addTearDown(gate.close);
    env = Env(
      environment: Environment.dev,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      workersCount: 1,
      maxConnectionCount: 4,
      blockRateLimitPerDay: 2,
      printEnv: false,
      isDebugModeOn: false,
    );
    final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning;
    });
    await configureDependencies(env);
    addTearDown(getIt.reset);
    await getIt.allReady(ignorePendingAsyncCreation: true);
    blocks = getIt<UserBlockCase>();
    invites = getIt<InvitationCase>();

    final recordingDb = TenturaDb(env, scopeInterceptor: () => recorder);
    addTearDown(recordingDb.close);
    recordedBlocks = _recordedBlockCase(env, recordingDb);
  });

  Future<Result> query(String sql, Map<String, Object> args) =>
      writer.execute(Sql.named(sql), parameters: args);

  Future<void> addUser(String id, int slot) => query(
    '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
    {'id': id, 'key': pgTestPublicKey('b${slot ~/ 9}', 1 + slot % 9)},
  );

  Future<_Pair> seedPair({
    bool withDeliveries = false,
    String? requestAuthor,
  }) async {
    final slot = ++nextPair;
    final suffix = slot.toString().padLeft(9, '0');
    final pair = (
      blocker: 'Uba$suffix',
      blocked: 'Ubb$suffix',
      request: 'Bba$suffix',
      reverseRequest: 'Bbb$suffix',
      invite: 'Iba$suffix',
    );
    await addUser(pair.blocker, slot * 2);
    await addUser(pair.blocked, slot * 2 + 1);
    await query(
      '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy, is_discoverable, published_at)
VALUES (@request, @author, 'A request', '', @status, @kind, 1, false, now()),
       (@reverse, @b, 'Another request', '', @status, @kind, 1, false, now())
''',
      {
        'author': requestAuthor ?? pair.blocker,
        'b': pair.blocked,
        'request': pair.request,
        'reverse': pair.reverseRequest,
        'status': BeaconStatus.open.smallintValue,
        'kind': BeaconKind.request.value,
      },
    );
    await query(
      '''
INSERT INTO public.invitation (id, user_id, beacon_id, addressee_name)
VALUES (@code, @a, @request, 'Invitee')
''',
      {'a': pair.blocker, 'request': pair.request, 'code': pair.invite},
    );
    if (withDeliveries) {
      await query(
        '''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@request, @a, @b), (@reverse, @b, @a)
''',
        {...pair.args, 'request': pair.request, 'reverse': pair.reverseRequest},
      );
      await query(
        '''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES (@a, @b, 'Invitee'), (@b, @a, 'Inviter')
''',
        pair.args,
      );
    }
    return pair;
  }

  Future<Result> edges(_Pair pair) => query('''
SELECT sender_id, recipient_id, cancelled_at IS NOT NULL
FROM public.beacon_forward_edge
WHERE (sender_id = @a AND recipient_id = @b)
   OR (sender_id = @b AND recipient_id = @a)
''', pair.args);

  Future<Result> contacts(_Pair pair) => query('''
SELECT viewer_id, subject_id
FROM public.user_contact
WHERE (viewer_id = @a AND subject_id = @b)
   OR (viewer_id = @b AND subject_id = @a)
''', pair.args);

  Future<Result> blockRows(_Pair pair) => query('''
SELECT blocker_id, blocked_id
FROM public.user_block
WHERE (blocker_id = @a AND blocked_id = @b)
   OR (blocker_id = @b AND blocked_id = @a)
''', pair.args);

  Future<Result> inbox(_Pair pair) => query(
    '''
SELECT user_id, beacon_id, status
FROM public.inbox_item
WHERE (user_id = @b AND beacon_id = @request)
   OR (user_id = @a AND beacon_id = @reverse)
''',
    {...pair.args, 'request': pair.request, 'reverse': pair.reverseRequest},
  );

  Future<void> block(_Pair pair, {UserBlockCase? useCase}) =>
      (useCase ?? blocks).block(
        blockerId: pair.blocker,
        blockedId: pair.blocked,
        cascadeMode: 0,
      );

  Future<void> unblock(_Pair pair, {UserBlockCase? useCase}) =>
      (useCase ?? blocks).unblock(
        blockerId: pair.blocker,
        blockedId: pair.blocked,
      );

  Future<bool> accept(_Pair pair) =>
      invites.acceptAsExisting(code: pair.invite, userId: pair.blocked);

  Future<bool> acceptOrHidden(_Pair pair) async {
    try {
      final accepted = await accept(pair);
      expect(
        accepted,
        isTrue,
        reason: 'a live invite must be accepted or hidden',
      );
      return accepted;
    } on IdNotFoundException {
      return false;
    }
  }

  Future<void> expectIntactPair(_Pair pair) async {
    expect(await edges(pair), unorderedEquals(pair.edgeRows(cancelled: false)));
    expect(await contacts(pair), unorderedEquals(pair.directions));
    expect(await blockRows(pair), isEmpty);
  }

  Future<void> expectBlockedPair(_Pair pair) async {
    expect(await blockRows(pair), [pair.directions.first]);
    expect((await edges(pair)).where((row) => row[2] == false), isEmpty);
    expect(await contacts(pair), isEmpty);
  }

  Future<void> expectAcceptedDelivery(_Pair pair) async {
    expect(await edges(pair), [pair.edgeRows(cancelled: false).first]);
    expect(await contacts(pair), [pair.directions.first]);
  }

  Future<void> waitForContactWriteGate(int gatePid, int count) async {
    final elapsed = Stopwatch()..start();
    while (true) {
      // A block can wait behind the accept, which is itself waiting at the gate.
      final waiting = await query(
        '''
WITH RECURSIVE blocked(pid) AS (
  SELECT @gate::int
  UNION
  SELECT activity.pid FROM pg_stat_activity AS activity
  JOIN blocked ON blocked.pid = ANY(pg_blocking_pids(activity.pid))
  WHERE activity.datname = current_database() AND activity.wait_event_type = 'Lock'
)
SELECT count(*) - 1 FROM blocked
''',
        {'gate': gatePid},
      );
      if ((waiting.single.single! as int) >= count) return;
      if (elapsed.elapsed >= kStableStateWait) {
        fail(
          'Expected $count transactions waiting behind the invite contact write',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<({Object? accept, Object? block})> raceBlockAgainstAccept(
    _Pair pair,
  ) async {
    final outcomes = <Future<Object?>>[];
    late List<Object?> errors;
    try {
      await gate.runTx((tx) async {
        final pid =
            (await tx.execute('SELECT pg_backend_pid()')).single.single! as int;
        await tx.execute(
          'SELECT pg_advisory_xact_lock($_contactWriteGate)',
        );

        outcomes.add(_captureError(acceptOrHidden(pair)));
        await waitForContactWriteGate(pid, 1);

        // The AFTER UPDATE trigger stops accept with its contact row locked.
        // Release it once block is waiting behind that live transaction.
        outcomes.add(_captureError(block(pair)));
        await waitForContactWriteGate(pid, 2);
      });
    } finally {
      errors = await Future.wait(outcomes).timeout(kCompletionWait);
    }
    return (accept: errors[0], block: errors[1]);
  }

  test(
    'Block withdraws offers and author invites, cancels forwards, and deletes contacts before writing trust',
    () async {
      final pair = await seedPair(withDeliveries: true);
      const firstOfferRequest = 'Boffer000001';
      const secondOfferRequest = 'Boffer000002';
      const offerRequests = {
        'first': firstOfferRequest,
        'second': secondOfferRequest,
      };
      final offerArgs = {...pair.args, ...offerRequests};
      // Withdrawing an offer leaves its inbox row watching. Use other Requests
      // so both invite deliveries still have new inbox rows to cancel.
      await query(
        '''
INSERT INTO public.beacon (id, user_id, title, description, status, is_discoverable, published_at)
VALUES (@first, @a, 'First offer', '', @status, true, now()),
       (@second, @b, 'Second offer', '', @status, true, now())
''',
        {...offerArgs, 'status': BeaconStatus.open.smallintValue},
      );
      await query('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message)
VALUES (@first, @b, 'I can help'), (@second, @a, 'I can help too')
''', offerArgs);
      final deliveryArgs = {
        'first': pair.request,
        'second': pair.reverseRequest,
      };
      await query('''
INSERT INTO public.beacon_author_invite
  (beacon_id, inviter_id, invitee_id, forward_edge_id, warm)
SELECT beacon_id, sender_id, recipient_id, id, true
FROM public.beacon_forward_edge
WHERE beacon_id IN (@first, @second)
''', deliveryArgs);

      Future<Result> offers() => query('''
SELECT beacon_id, user_id, status, withdraw_reason
FROM public.beacon_help_offer
WHERE beacon_id IN (@first, @second)
''', offerRequests);
      Matcher offerState(int status, String? reason) => unorderedEquals([
        [firstOfferRequest, pair.blocked, status, reason],
        [secondOfferRequest, pair.blocker, status, reason],
      ]);
      Future<Result> authorInvites() => query('''
SELECT beacon_id, inviter_id, invitee_id, status, resolved_at IS NOT NULL
FROM public.beacon_author_invite
WHERE beacon_id IN (@first, @second)
''', deliveryArgs);
      Matcher authorInviteState(
        AuthorInviteStatus status, {
        required bool resolved,
      }) => unorderedEquals([
        [pair.request, pair.blocker, pair.blocked, status.code, resolved],
        [
          pair.reverseRequest,
          pair.blocked,
          pair.blocker,
          status.code,
          resolved,
        ],
      ]);

      await expectIntactPair(pair);
      expect(await inbox(pair), unorderedEquals(pair.inboxRows(0)));
      expect(await offers(), offerState(0, null));
      expect(
        await authorInvites(),
        authorInviteState(AuthorInviteStatus.pending, resolved: false),
      );

      recorder.events.clear();
      await block(pair, useCase: recordedBlocks);

      await expectBlockedPair(pair);
      expect(
        await edges(pair),
        unorderedEquals(pair.edgeRows(cancelled: true)),
      );
      // 3 is the persisted "closed before response" status for a cancelled forward.
      expect(await inbox(pair), unorderedEquals(pair.inboxRows(3)));
      expect(await offers(), offerState(1, kBlockWithdrawReason));
      expect(
        await authorInvites(),
        authorInviteState(AuthorInviteStatus.withdrawn, resolved: true),
      );
      final events = recorder.events;
      final scope = events.indexOf('hierarchy lock');
      final insert = events.indexOf('block insert');
      const cleanupWrites = {
        'help offer withdrawal',
        'author invite withdrawal',
        'forward update',
        'contact delete',
      };
      final cleanup = events.indexed.where(
        (entry) => cleanupWrites.contains(entry.$2),
      );
      final cancels = events.indexed.where(
        (entry) => entry.$2 == 'forward update',
      );
      final deletes = events.indexed.where(
        (entry) => entry.$2 == 'contact delete',
      );
      expect(scope, greaterThanOrEqualTo(0));
      expect(insert, greaterThan(scope));
      expect(cleanup.map((entry) => entry.$2), containsAll(cleanupWrites));
      expect(
        cleanup.where((entry) => entry.$1 <= scope || entry.$1 >= insert),
        isEmpty,
        reason:
            'offer, author invite, forward and contact writes must follow the hierarchy lock '
            'and precede the block insert. Observed: $events',
      );
      expect(cancels.last.$1, lessThan(deletes.first.$1));
    },
  );

  test(
    'Block rate limit leaves both forwards and both contacts intact',
    () async {
      final pair = await seedPair(withDeliveries: true);
      for (var i = 0; i < env.blockRateLimitPerDay; i++) {
        final other = await seedPair();
        await blocks.block(
          blockerId: pair.blocker,
          blockedId: other.blocked,
          cascadeMode: 0,
        );
      }
      await expectLater(block(pair), throwsA(isA<RateLimitedException>()));
      await expectIntactPair(pair);
    },
  );

  test('Unknown user and self-block requests leave the pair intact', () async {
    final pair = await seedPair(withDeliveries: true);
    await expectLater(
      blocks.block(
        blockerId: pair.blocker,
        blockedId: _missingUser,
        cascadeMode: 0,
      ),
      throwsA(isA<IdNotFoundException>()),
    );
    await expectIntactPair(pair);
    expect(
      await query(
        'SELECT blocked_id FROM public.user_block WHERE blocker_id = @a',
        {'a': pair.blocker},
      ),
      isEmpty,
    );
    expect(
      () => blocks.block(
        blockerId: pair.blocker,
        blockedId: pair.blocker,
        cascadeMode: 0,
      ),
      throwsArgumentError,
    );
    await expectIntactPair(pair);
  });

  test(
    'Unblock finishes with trust projection after removing the block',
    () async {
      final pair = await seedPair(withDeliveries: true);
      await block(pair);
      await expectBlockedPair(pair);

      recorder.events.clear();
      await unblock(pair, useCase: recordedBlocks);

      expect(await blockRows(pair), isEmpty);
      final events = recorder.events;
      final deletion = events.indexOf('block delete');
      expect(deletion, greaterThanOrEqualTo(0));
      expect(
        events.skip(deletion + 1),
        isNot(
          anyElement(
            anyOf(
              'forward update',
              'forward write',
              'contact delete',
              'contact write',
            ),
          ),
        ),
      );
      expect(events.take(deletion), contains('hierarchy lock'));
      expect(events.skip(events.length - 2), ['trust projection', 'commit']);
    },
  );

  test(
    'Blocking an invitee after acceptance removes the delivered forward and contact',
    () async {
      final pair = await seedPair();
      expect(await accept(pair), isTrue);
      await expectAcceptedDelivery(pair);

      await block(pair);

      await expectBlockedPair(pair);
      expect(await edges(pair), [pair.edgeRows(cancelled: true).first]);
    },
  );

  test(
    'An invite cannot deliver a forward or contact after the inviter blocks the recipient',
    () async {
      final pair = await seedPair();
      await block(pair);

      await expectLater(accept(pair), throwsA(isA<IdNotFoundException>()));

      await expectBlockedPair(pair);
      expect(await edges(pair), isEmpty);
    },
  );

  test(
    'Concurrent block and Request invite acceptance leave no forward or contact between the pair',
    () async {
      const requestAuthor = 'Ureqauthor01';
      await addUser(requestAuthor, 0);
      await writer.execute('''
CREATE FUNCTION block_invite_test_pause_contact_write() RETURNS trigger
LANGUAGE plpgsql AS \$\$
BEGIN
  PERFORM pg_advisory_xact_lock($_contactWriteGate);
  RETURN NULL;
END
\$\$;
CREATE TRIGGER block_invite_test_contact_write
AFTER UPDATE ON public.user_contact
FOR EACH ROW
WHEN (OLD.contact_name = 'Saved recipient' AND NEW.contact_name = 'Invitee')
EXECUTE FUNCTION block_invite_test_pause_contact_write();
''', queryMode: QueryMode.simple);
      final survivingEdges = <ResultRow>[];
      final survivingContacts = <ResultRow>[];
      final missingBlocks = <String>[];
      final callerErrors = <String, Object>{};
      for (var i = 0; i < 10; i++) {
        final pair = await seedPair(requestAuthor: requestAuthor);
        // Forwarding a received Request engages its parent edge and projects
        // trust in the same transaction that updates the existing contact.
        await query(
          '''
WITH parent AS (
  INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
  VALUES (@request, @author, @a)
  RETURNING id
)
UPDATE public.invitation
SET parent_forward_edge_id = (SELECT id FROM parent)
WHERE id = @code
''',
          {
            'request': pair.request,
            'author': requestAuthor,
            'a': pair.blocker,
            'code': pair.invite,
          },
        );
        await query('''
INSERT INTO public.user_contact (viewer_id, subject_id, contact_name)
VALUES (@a, @b, 'Saved recipient')
''', pair.args);

        final result = await raceBlockAgainstAccept(pair);
        if (result.accept case final error?) {
          callerErrors['accept ${pair.invite}'] = error;
        }
        if (result.block case final error?) {
          callerErrors['block ${pair.blocker}'] = error;
        }
        final rows = await blockRows(pair);
        if (rows.length != 1 ||
            rows.single[0] != pair.blocker ||
            rows.single[1] != pair.blocked) {
          missingBlocks.add(pair.blocker);
        }
        survivingEdges.addAll(
          (await edges(pair)).where((row) => row[2] == false),
        );
        survivingContacts.addAll(await contacts(pair));
      }
      expect(
        {
          'caller errors': callerErrors,
          'missing or unexpected blocks': missingBlocks,
          'active forwards': survivingEdges,
          'contacts': survivingContacts,
        },
        {
          'caller errors': isEmpty,
          'missing or unexpected blocks': isEmpty,
          'active forwards': isEmpty,
          'contacts': isEmpty,
        },
      );
    },
  );

  test(
    'Concurrent unblock and Request invite acceptance complete with the pair unblocked',
    () async {
      final pair = await seedPair();
      await block(pair);
      await expectBlockedPair(pair);

      final outcomes = await Future.wait<Object?>([
        unblock(pair).then((_) => null),
        acceptOrHidden(pair),
      ]).timeout(kCompletionWait);

      expect(await blockRows(pair), isEmpty);
      if (outcomes.last == true) {
        await expectAcceptedDelivery(pair);
      }
    },
  );
}

Future<Object?> _captureError(Future<void> operation) async {
  try {
    await operation;
    return null;
  } on Object catch (error) {
    return error;
  }
}

typedef _Pair = ({
  String blocker,
  String blocked,
  String request,
  String reverseRequest,
  String invite,
});

extension on _Pair {
  Map<String, String> get args => {'a': blocker, 'b': blocked};

  List<List<String>> get directions => [
    [blocker, blocked],
    [blocked, blocker],
  ];

  List<List<Object>> edgeRows({required bool cancelled}) => [
    for (final pair in directions) [...pair, cancelled],
  ];

  List<List<Object>> inboxRows(int status) => [
    [blocked, request, status],
    [blocker, reverseRequest, status],
  ];
}

UserBlockCase _recordedBlockCase(Env env, TenturaDb db) {
  final witnessWindow = WitnessWindowRepository(db);
  final blocks = UserBlockRepository(env, db, witnessWindow: witnessWindow);
  return UserBlockCase(
    MutatingUnitOfWork(db),
    blocks,
    HelpOfferRepository(db),
    ForwardEdgeRepository(db),
    UserContactRepository(db),
    UserRepository(
      env,
      db,
      InviteGenealogyRepository(env, db, blocks),
      InviteSeedPromptRepository(db),
    ),
    BeaconRepository(db),
    CommitmentRepository(db),
    InboxRepository(db),
    CapabilityEvidenceRepository(db),
    BeaconHierarchyRepository(db),
    roomRepository: BeaconRoomRepository(db),
    trustLedger: TrustLedgerRepository(db),
    witnessWindow: witnessWindow,
    authorInvites: AuthorInviteRepository(db),
    env: env,
    logger: getIt(),
  );
}

final class _BlockStatements extends QueryInterceptor {
  final events = <String>[];

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement, args);
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    events.add('commit');
    return super.commitTransaction(inner);
  }

  static final _write = RegExp(r'\b(insert into|update|delete from) (\w+)\b');
  static final _whitespace = RegExp(r'\s+');

  void _record(String statement, List<Object?> args) {
    final sql = statement
        .toLowerCase()
        .replaceAll('"', '')
        .replaceAll('public.', '')
        .replaceAll(_whitespace, ' ')
        .trim();
    if (sql.contains('beacon_hierarchy_acquire_mutation_lock') ||
        sql.contains('pg_advisory_xact_lock') &&
            (sql.contains('tentura.beacon_hierarchy.v1') ||
                args.contains('tentura.beacon_hierarchy.v1'))) {
      events.add('hierarchy lock');
    } else if (sql.contains('trust_project_pair(')) {
      events.add('trust projection');
    } else if (_write.firstMatch(sql) case final write?) {
      events.add(switch ((write[1], write[2])) {
        ('insert into', 'user_block') => 'block insert',
        ('delete from', 'user_block') => 'block delete',
        ('update', 'beacon_help_offer') => 'help offer withdrawal',
        ('update', 'beacon_author_invite') => 'author invite withdrawal',
        ('update', 'beacon_forward_edge') => 'forward update',
        (_, 'beacon_forward_edge') => 'forward write',
        ('delete from', 'user_contact') => 'contact delete',
        (_, 'user_contact') => 'contact write',
        _ => write[0]!,
      });
    }
  }
}
