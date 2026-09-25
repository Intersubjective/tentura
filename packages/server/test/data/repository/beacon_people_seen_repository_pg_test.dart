@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_people_seen_repository.dart';
import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';

import '../../support/disposable_pg_target.dart';

/// Issue #178 plan P1.2: [BeaconPeopleSeenRepositoryPort] monotonic upsert
/// and batch lookup over `beacon_people_seen` (m0198).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_PEOPLE_SEEN_REPO_TEST_DB',
    defaultNamePrefix: 'tentura_test_people_seen_repo',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('BeaconPeopleSeenRepository', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late BeaconPeopleSeenRepositoryPort repo;
    late Connection listener;
    late StreamSubscription<String> subscription;
    final notifications = <Map<String, dynamic>>[];

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      db = openDisposablePgDatabase(target);
      repo = BeaconPeopleSeenRepository(db);
      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      subscription = listener.channels['entity_changes'].listen(
        (payload) =>
            notifications.add(jsonDecode(payload) as Map<String, dynamic>),
      );
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_people_seen,
  public.beacon_help_offer,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_authorId, _offerer, _other]) {
        await writer.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES
  (@b1, @author, 'One', 'First request', 0),
  (@b2, @author, 'Two', 'Second request', 0)
'''),
        parameters: {'b1': _beaconId, 'b2': _otherBeaconId, 'author': _authorId},
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status)
VALUES (@b1, @offerer, 'I can help', 0), (@b1, @other, 'Me too', 0)
'''),
        parameters: {'b1': _beaconId, 'offerer': _offerer, 'other': _other},
      );
      await _settle();
      notifications.clear();
    });

    tearDownAll(() async {
      await subscription.cancel();
      await listener.close();
      await tearDownDisposablePgWriter(session: session, drift: db);
    });

    List<Map<String, dynamic>> peopleSeen() =>
        notifications.where((m) => m['entity'] == 'people_seen').toList();

    // The repo write committed before this NOTIFY, and Postgres delivers
    // notifications in commit order, so once the marker arrives any
    // people_seen from the write has too.
    Future<void> barrier() async {
      final id = 'barrier-${DateTime.timestamp().microsecondsSinceEpoch}';
      await writer.execute(
        Sql.named("SELECT pg_notify('entity_changes', @payload)"),
        parameters: {'payload': jsonEncode({'entity': 'barrier', 'id': id})},
      );
      await _waitUntil(() => notifications.any((m) => m['id'] == id));
    }

    test('first markSeen returns at', () async {
      final at = DateTime.utc(2026, 9, 1, 12);
      final stored = await repo.markSeen(
        userId: _authorId,
        beaconId: _beaconId,
        at: at,
      );
      expect(stored, at);
      expect(stored.isUtc, isTrue);
    });

    test(
      'older at returns the newer stored value and emits no people_seen',
      () async {
        final newer = DateTime.utc(2026, 9, 2, 12);
        await repo.markSeen(userId: _authorId, beaconId: _beaconId, at: newer);
        await _waitUntil(() => peopleSeen().isNotEmpty);
        await _settle();
        notifications.clear();

        final stored = await repo.markSeen(
          userId: _authorId,
          beaconId: _beaconId,
          at: DateTime.utc(2026, 9, 2, 10),
        );
        await barrier();

        expect(stored, newer);
        expect(peopleSeen(), isEmpty);
      },
    );

    test('newer at advances and NOTIFY carries the caller as actor', () async {
      // Caller is an active offerer, distinct from the request author.
      await repo.markSeen(
        userId: _offerer,
        beaconId: _beaconId,
        at: DateTime.utc(2026, 9, 3, 10),
      );
      await _waitUntil(() => peopleSeen().isNotEmpty);
      await _settle();
      notifications.clear();

      final advanced = DateTime.utc(2026, 9, 3, 11);
      final stored = await repo.markSeen(
        userId: _offerer,
        beaconId: _beaconId,
        at: advanced,
      );
      await _waitUntil(() => peopleSeen().isNotEmpty);
      await _settle();

      expect(stored, advanced);
      expect(peopleSeen(), hasLength(1));
      expect(peopleSeen().single['actor_user_id'], _offerer);
      expect(peopleSeen().single['actor_user_id'], isNot(_authorId));
    });

    test(
      'lastSeenByUserIds returns every id with a row, scoped to the beacon, '
      'in one SELECT',
      () async {
        final authorAt = DateTime.utc(2026, 9, 4, 12);
        final offererAt = DateTime.utc(2026, 9, 4, 13);
        await repo.markSeen(
          userId: _authorId,
          beaconId: _beaconId,
          at: authorAt,
        );
        await repo.markSeen(
          userId: _offerer,
          beaconId: _beaconId,
          at: offererAt,
        );
        await repo.markSeen(
          userId: _offerer,
          beaconId: _otherBeaconId,
          at: DateTime.utc(2026, 9, 4, 18),
        );
        await repo.markSeen(
          userId: _other,
          beaconId: _otherBeaconId,
          at: DateTime.utc(2026, 9, 4, 19),
        );

        final interceptor = _SelectCounter();
        final result = await db.runWithInterceptor(
          () => repo.lastSeenByUserIds(
            beaconId: _beaconId,
            userIds: [_authorId, _offerer, _other],
          ),
          interceptor: interceptor,
        );

        expect(result, {_authorId: authorAt, _offerer: offererAt});
        expect(interceptor.selects, hasLength(1));
        expect(interceptor.selects.single, contains('beacon_people_seen'));
      },
    );

    test(
      'lastSeenByUserIds returns {} for an empty id list without a SELECT',
      () async {
        final interceptor = _SelectCounter();
        final result = await db.runWithInterceptor(
          () => repo.lastSeenByUserIds(beaconId: _beaconId, userIds: const []),
          interceptor: interceptor,
        );

        expect(result, isEmpty);
        expect(interceptor.selects, isEmpty);
      },
    );
  }, skip: skipReason);
}

const _authorId = 'Upsrepo01';
const _offerer = 'Upsrepo02';
const _other = 'Upsrepo03';
const _beaconId = 'Bpsrepo01';
const _otherBeaconId = 'Bpsrepo02';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _SelectCounter extends QueryInterceptor {
  final selects = <String>[];

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add(statement);
    return executor.runSelect(statement, args);
  }
}
