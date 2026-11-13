@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// Fact history must be scoped to the beacon id the caller passes: a member of
/// one Request must not read another Request's fact revisions when they reuse
/// a fact card id (plan §5.0 / X10).
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_HISTORY_BEACON_SCOPE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_history_beacon_scope',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late _SelectRecorder recorder;
  late BeaconFactCardCase useCase;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    await _seed(session.writer);

    recorder = _SelectRecorder();
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ).interceptWith(recorder),
    );
    final room = BeaconRoomRepository(db);
    useCase = BeaconFactCardCase(
      BeaconFactCardRepository(db, room),
      room,
      _UnusedImage(),
      _UnusedTasks(),
      BeaconHierarchyRepository(db),
      BeaconAccessRepository(db),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardHistoryBeaconScopePgTest'),
    );
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  group('BeaconFactCardCase.history is scoped to the beacon id', () {
    test(
      'throws IdNotFound when the fact card belongs to another Request',
      () async {
        await expectLater(
          useCase.history(
            factCardId: _factInA,
            beaconId: _beaconB,
            userId: _memberB,
          ),
          throwsA(isA<IdNotFoundException>()),
        );
      },
    );

    test(
      'scopes the history UNION to the beacon id in the same SELECT',
      () async {
        recorder.reset();
        Object? outcome;
        try {
          await useCase.history(
            factCardId: _factInA,
            beaconId: _beaconB,
            userId: _memberB,
          );
        } on Object catch (e) {
          outcome = e;
        }

        final historySelects = recorder.selects
            .where((s) => s.statement.contains('beacon_fact_card_revision'))
            .toList();
        expect(
          historySelects,
          hasLength(1),
          reason: 'one keyset history SELECT (outcome: $outcome)',
        );
        final stmt = historySelects.single.statement;
        expect(
          stmt,
          contains('public.beacon_fact_card'),
          reason: 'history must join the fact row to enforce beacon scope',
        );
        expect(
          stmt,
          matches(
            RegExp(
              r'f\.beacon_id\s*=\s*\$|beacon_id\s*=\s*\$\d+::text',
              multiLine: true,
            ),
          ),
          reason: 'beacon id must be bound in the history statement:\n$stmt',
        );
      },
    );

    test(
      'returns an empty page when the cursor is past the last entry',
      () async {
        final page = await useCase.history(
          factCardId: _factInA,
          beaconId: _beaconA,
          userId: _memberA,
          before:
              '${_beforeAllEntries.toUtc().toIso8601String()}|r0000000000',
        );
        expect(page.entries, isEmpty);
        expect(page.nextCursor, isNull);
      },
    );

    test(
      'pages every revision and event for a fact in the same Request',
      () async {
        String? cursor;
        var seen = 0;
        var pages = 0;
        while (true) {
          pages++;
          expect(pages, lessThan(5), reason: 'paging must terminate');
          final page = await useCase.history(
            factCardId: _factInA,
            beaconId: _beaconA,
            userId: _memberA,
            before: cursor,
          );
          seen += page.entries.length;
          cursor = page.nextCursor;
          if (cursor == null) break;
        }
        expect(seen, _fixtureEntryCount);
      },
    );
  });
}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

const _authorA = 'Ufhbscauthor';
const _memberA = 'Ufhbscmembra';
const _memberB = 'Ufhbscmembrb';

const _beaconA = 'BfhbscbeacA';
const _beaconB = 'BfhbscbeacB';
const _factInA = 'FfhbscfactA1';

const _revisionCount = 3;
const _eventCount = 55;
const _fixtureEntryCount = _revisionCount + _eventCount;

final _t0 = DateTime.utc(2026, 6, 1, 9);
final _beforeAllEntries = _t0.subtract(const Duration(days: 1));

Future<void> _seed(Connection writer) async {
  const users = [_authorA, _memberA, _memberB];
  for (final (index, id) in users.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('fhbscope', index + 1)},
    );
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind, published_at)
VALUES ('$_beaconA', '$_authorA', 'Request A', '', 0, 0, now()),
       ('$_beaconB', '$_authorA', 'Request B', '', 0, 0, now())
''');

  await writer.execute('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
VALUES ('PfhbscA', '$_beaconA', '$_memberA', 0, 0, 3),
       ('PfhbscB', '$_beaconB', '$_memberB', 0, 0, 3)
''');

  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   created_at, updated_at)
VALUES (@id, @beacon, 'Fact in A', ${BeaconFactCardVisibilityBits.public},
        @author, ${BeaconFactCardStatusBits.active}, $_revisionCount, @t0, @t0)
'''),
    parameters: {
      'id': _factInA,
      'beacon': _beaconA,
      'author': _authorA,
      't0': _t0,
    },
  );

  for (var seq = 1; seq <= _revisionCount; seq++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, created_at)
VALUES (@fact, @seq, @text, @actor, @kind, @at)
'''),
      parameters: {
        'fact': _factInA,
        'seq': seq,
        'text': 'Fact in A v$seq',
        'actor': _authorA,
        'kind': seq == 1
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.edited,
        'at': _t0.add(Duration(minutes: seq)),
      },
    );
  }

  for (var i = 0; i < _eventCount; i++) {
    final type = switch (i) {
      0 => BeaconActivityEventTypeBits.factPinned,
      _ => BeaconActivityEventTypeBits.factVisibilityChanged,
    };
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_activity_event
  (id, beacon_id, visibility, type, actor_id, fact_card_id, diff, created_at)
VALUES (@id, @beacon, 0, @type, @actor, @fact,
        jsonb_build_object('factCardId', @fact::text), @at)
'''),
      parameters: {
        'id': 'Vfhbsc${i.toString().padLeft(3, '0')}',
        'beacon': _beaconA,
        'type': type,
        'actor': _authorA,
        'fact': _factInA,
        'at': _t0.add(Duration(minutes: 10 + i)),
      },
    );
  }
}

class _SelectRecorder extends QueryInterceptor {
  final selects = <({String statement, List<Object?> args})>[];

  void reset() => selects.clear();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects.add((statement: statement, args: List.of(args)));
    return super.runSelect(executor, statement, args);
  }
}
