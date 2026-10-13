import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_clear_repository.dart';
import 'package:tentura_server/data/repository/attention_cutover_repository.dart';
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/data/repository/bud_anchor_sweep_repository.dart';
import 'package:tentura_server/data/repository/capability_cell_repository.dart';
import 'package:tentura_server/data/repository/closure_repository.dart';
import 'package:tentura_server/data/repository/fcm_token_repository.dart';
import 'package:tentura_server/data/repository/polling_act_repository.dart';
import 'package:tentura_server/data/repository/trust_cutover_repository.dart';
import 'package:tentura_server/data/repository/trust_maintenance_sweep_repository.dart';
import 'package:tentura_server/data/repository/trust_publish_repository.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/data/service/main_db_scope_admission.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/env.dart';
import 'package:test/test.dart';

typedef _ActorPath = Future<void> Function(TenturaDb database, String actor);

void main() {
  final actorPaths = <String, _ActorPath>{
    'attention capture': (db, actor) => AttentionClearRepository(
      db,
    ).captureEligible(accountId: actor, beaconId: null),
    'attention clear': (db, actor) => AttentionClearRepository(db).apply(
      accountId: actor,
      operationId: 'clear-$actor',
      beaconId: null,
      kind: AttentionClearCaptureKind.explicit,
      outcomeGeneration: 0,
      decisionRevision: 0,
      receiptIds: const [],
    ),
    'attention sweep': (db, actor) => AttentionSweepRepository(db).dismissAll(
      accountId: actor,
      operationId: 'sweep-$actor',
    ),
    'attention undo': (db, actor) => AttentionSweepRepository(db).undo(
      accountId: actor,
      operationId: 'sweep-$actor',
      undoToken: '',
    ),
    'block': (db, actor) => UserBlockRepository(_env(), db).block(
      blockerId: actor,
      blockedId: 'peer',
      cascadeMode: 0,
    ),
    'unblock': (db, actor) => UserBlockRepository(_env(), db).unblock(
      blockerId: actor,
      blockedId: 'peer',
    ),
    'promote block': (db, actor) => UserBlockRepository(
      _env(),
      db,
    ).promoteToDirect(blockerId: actor, blockedId: 'peer'),
    'poll vote': (db, actor) => PollingActRepository(db).upsert(
      authorId: actor,
      pollingId: 'poll',
      variantIds: const ['variant'],
      pollType: 'single',
      allowRevote: true,
    ),
    'push token': (db, actor) => FcmTokenRepository(db).putToken(
      userId: actor,
      appId: '00000000-0000-4000-8000-000000000001',
      token: 'token',
      platform: 'test',
    ),
    'witness window': (db, actor) => WitnessWindowRepository(db).storeWindow(
      egoId: actor,
      normalizedContext: '',
      weights: const [],
    ),
    'QA seed': (db, actor) => ClosureRepository(db).seedQaRequestWithHelpers(
      authorId: actor,
      helperIds: const [],
      title: 'Seed',
    ),
    'implicit V2 query': (db, actor) => MainDbWorkContext.run(
      () => db.customStatement('SELECT 1'),
      actorUserId: actor,
    ),
  };

  for (final entry in actorPaths.entries) {
    test('${entry.key} respects the shared per-user waiting cap', () async {
      final fixture = await _Fixture.holdSlots();
      final tickets = <_Ticket>[];
      try {
        for (var index = 0; index < 7; index++) {
          tickets.add(_Ticket(entry.value(fixture.database, 'flooding-actor')));
        }
        await _settle();
        expect(fixture.pool.admission.queued, 4);
        expect(tickets.where((ticket) => ticket.completed), hasLength(3));
        for (final ticket in tickets.where((ticket) => ticket.completed)) {
          expect(ticket.error, _retryLater);
        }

        final other = _Ticket(entry.value(fixture.database, 'other-actor'));
        tickets.add(other);
        await _settle();
        expect(other.completed, isFalse);
        expect(fixture.pool.admission.queued, 5);
      } finally {
        await fixture.close();
        await Future.wait(tickets.map((ticket) => ticket.done));
      }
    });
  }

  test(
    'clear and sweep share one actor budget across database handles',
    () async {
      final fixture = await _Fixture.holdSlots();
      final otherDatabase = TenturaDb.scoped(fixture.pool);
      final tickets = <_Ticket>[];
      try {
        for (var index = 0; index < 7; index++) {
          final database = index.isEven ? fixture.database : otherDatabase;
          final path =
              actorPaths[index.isEven ? 'attention clear' : 'attention sweep']!;
          tickets.add(_Ticket(path(database, 'same-actor')));
        }
        await _settle();
        expect(fixture.pool.admission.queued, 4);
        expect(tickets.where((ticket) => ticket.completed), hasLength(3));
        for (final ticket in tickets.where((ticket) => ticket.completed)) {
          expect(ticket.error, _retryLater);
        }
      } finally {
        await fixture.close();
        await otherDatabase.close();
        await Future.wait(tickets.map((ticket) => ticket.done));
      }
    },
  );

  test(
    'maintenance paths share the FULL limit and expire without starting SQL',
    () async {
      final fixture = await _Fixture.holdSlots(heavyOnly: true);
      final db = fixture.database;
      final tickets = <_Ticket>[];
      try {
        final maintenancePaths = <Future<void> Function()>[
          () => AttentionCutoverRepository(
            db,
          ).convertLegacySeenBatch(batchSize: 1),
          () => AttentionCutoverRepository(
            db,
          ).keyLegacyObligationBatch(batchSize: 1),
          () => AttentionCutoverRepository(
            db,
          ).demoteLegacyPlacementBatch(batchSize: 1),
          () => TrustMaintenanceSweepRepository(db).projectNextBatch(
            afterSubject: '',
            afterObject: '',
            batchSize: 1,
          ),
          () => TrustCutoverRepository(
            db,
          ).projectPairs(1, [('subject', 'object')]),
          () => TrustCutoverRepository(
            db,
          ).projectBanPairs([('subject', 'object')]),
          () => TrustCutoverRepository(db).reset(1),
          () => TrustCutoverRepository(db).init(1),
          () => TrustCutoverRepository(db).sync(1),
          () => TrustCutoverRepository(db).finish(1),
          () => TrustPublishRepository(
            db,
          ).publish(const PublishRow('subject', 'object', 1)),
          () => TrustPublishRepository(db).sync(),
          () => TrustPublishRepository(
            db,
          ).ack(1, const [PublishRow('subject', 'object', 1)]),
          () => TrustPublishRepository(
            db,
          ).fail(const [PublishRow('subject', 'object', 1)], 'test'),
          () => CapabilityCellRepository(db).gcOrphanGenerations(limit: 1),
          () => UserAvailabilityRepository(
            db,
          ).cleanupExpired(DateTime.utc(2026, 10, 12)),
          () => BudAnchorSweepRepository(
            db,
          ).markInherited(actorUserId: 'actor', clientCommandId: 'command'),
          () => UserBlockRepository(_env(), db).materializeCascadeBatch(
            blockerId: 'actor',
            blockedId: 'peer',
            limit: 1,
          ),
          () => UserBlockRepository(_env(), db).runReleaseSweep(limit: 1),
          () => actorPaths['attention sweep']!(db, 'sweeping-actor'),
          () => actorPaths['attention undo']!(db, 'undoing-actor'),
        ];
        for (final path in maintenancePaths) {
          tickets.add(_Ticket(path()));
        }
        await _settle();
        expect(fixture.pool.admission.running, 1);
        expect(fixture.pool.admission.queued, maintenancePaths.length);
        expect(tickets.where((ticket) => ticket.completed), isEmpty);

        // Heavy waiters do not consume the remaining interactive slots.
        await fixture.pool.admission.run(() async {});
        await Future.wait(tickets.map((ticket) => ticket.done));
        for (final ticket in tickets) {
          expect(ticket.error, _retryLater);
        }
        expect(fixture.pool.admission.queued, 0);
        expect(fixture.pool.admission.running, 1);
        // No PostgreSQL endpoint is needed: any path that starts SQL would fail
        // with a connection error instead of the required admission refusal.
      } finally {
        await fixture.close();
        await Future.wait(tickets.map((ticket) => ticket.done));
      }
      await _settle();
      expect(fixture.pool.admission.running, 0);
    },
  );

  test('admission metadata alone never leases a connection', () async {
    final pool = MainDbPool(_env());
    final database = TenturaDb.scoped(pool);
    final release = Completer<void>();
    final work = database.withWorkContext(
      () => release.future,
      actorUserId: 'actor',
      kind: MainDbWorkKind.full,
    );
    try {
      await _settle();
      expect(pool.admission.running, 0);
      expect(pool.admission.queued, 0);
      expect(MainDbWorkContext.current, isNull);
    } finally {
      release.complete();
      await work;
      await database.close();
      await pool.close();
    }
  });
}

Matcher get _retryLater => isA<ConstellationException>().having(
  (error) => (error.code as ConstellationExceptionCodes).exceptionCode,
  'exceptionCode',
  ConstellationExceptionCode.retryLater,
);

Env _env() => Env(
  environment: Environment.test,
  printEnv: false,
  maxConnectionCount: 4,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

final class _Ticket {
  _Ticket(Future<void> work) {
    done = work.then<void>(
      (_) => completed = true,
      onError: (Object failure) {
        error = failure;
        completed = true;
      },
    );
  }

  late final Future<void> done;
  bool completed = false;
  Object? error;
}

final class _Fixture {
  _Fixture() : pool = MainDbPool(_env()) {
    database = TenturaDb.scoped(pool);
  }

  final MainDbPool pool;
  late final TenturaDb database;
  final release = Completer<void>();
  final holders = <Future<void>>[];

  static Future<_Fixture> holdSlots({bool heavyOnly = false}) async {
    final fixture = _Fixture();
    for (var index = 0; index < (heavyOnly ? 1 : 4); index++) {
      fixture.holders.add(
        fixture.pool.admission.run(
          () => fixture.release.future,
          kind: heavyOnly ? MainDbWorkKind.full : MainDbWorkKind.interactive,
        ),
      );
    }
    await _settle();
    return fixture;
  }

  Future<void> close() async {
    pool.admission.close();
    release.complete();
    await Future.wait(holders);
    await database.close();
    await pool.close();
  }
}
