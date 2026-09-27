import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_fact_history_cursor_contract.dart';
import '../../support/fake_beacon_access_guard.dart';

/// tentura-617.14 (issue #181 plan §8.4, §8.11, D1): `BeaconFactCardCase`
/// gains a read-only `history` method that:
///  - runs the fused `loadRoomAccess` preflight and requires `canUseRoom`
///    (members only — not `canReadContent`, unlike `list`);
///  - parses the opaque `'<iso8601UTC>|<entry_key>'` cursor into the port's
///    `before` keyset argument, and rejects a malformed cursor with
///    `IdWrongException` *before* calling the port's `history()`;
///  - trims the port's `limit + 1` look-ahead to `kFactHistoryPageSize`
///    entries and serialises the last kept entry as the opaque `nextCursor`,
///    which is `null` iff the port returned no look-ahead row.
const _beaconId = 'Bhistaaaaaaa';
const _userId = 'Uhistaaaaaaa';
const _factId = 'Fhistaaaaaaa';

final _t0 = DateTime.utc(2026, 3, 1, 12);

DateTime _at(int seq) => _t0.add(Duration(minutes: seq));

String _revisionKey(int seq) => 'r${seq.toString().padLeft(10, '0')}';

/// Revisions seq [count] down to 1, newest (highest seq) first — the same
/// order the port's real UNION query returns.
List<BeaconFactHistoryEntry> _revisionsDesc(int count) => [
  for (var seq = count; seq >= 1; seq--)
    BeaconFactHistoryRevision(
      seq: seq,
      kind: BeaconFactCardRevisionKindBits.edited,
      factText: 'v$seq',
      actorTitle: 'Actor',
      createdAt: _at(seq),
    ),
];

/// Persisted `beacon_activity_event.id` for the page-1 boundary event.
const _boundaryActivityEventId = 'Evhist000001';

/// Newest-first timeline where page 1's last kept row is a fact event and two
/// older revisions remain (52 rows total).
List<BeaconFactHistoryEntry> _eventBoundaryCatalog() {
  final boundaryEvent = BeaconFactHistoryEntry.event(
    activityEventId: _boundaryActivityEventId,
    type: BeaconActivityEventTypeBits.factVisibilityChanged,
    actorTitle: 'Actor',
    createdAt: _at(2),
  );
  return [
    for (var seq = 51; seq >= 3; seq--)
      BeaconFactHistoryRevision(
        seq: seq,
        kind: BeaconFactCardRevisionKindBits.edited,
        factText: 'v$seq',
        actorTitle: 'Actor',
        createdAt: _at(seq),
      ),
    boundaryEvent,
    BeaconFactHistoryRevision(
      seq: 2,
      kind: BeaconFactCardRevisionKindBits.edited,
      factText: 'v2',
      actorTitle: 'Actor',
      createdAt: _at(1),
    ),
    BeaconFactHistoryRevision(
      seq: 1,
      kind: BeaconFactCardRevisionKindBits.edited,
      factText: 'v1',
      actorTitle: 'Actor',
      createdAt: _at(0),
    ),
  ];
}

({DateTime createdAt, String entryKey}) _parseOpaqueCursor(String cursor) {
  final sep = cursor.indexOf('|');
  return (
    createdAt: DateTime.parse(cursor.substring(0, sep)).toUtc(),
    entryKey: cursor.substring(sep + 1),
  );
}

String _describeEntry(BeaconFactHistoryEntry entry) => switch (entry) {
  BeaconFactHistoryRevision(:final seq) => 'revision:$seq',
  BeaconFactHistoryEvent(:final type) => 'event:$type',
};

typedef _HistoryCall = ({
  String factCardId,
  ({DateTime createdAt, String entryKey})? before,
  int limit,
});

class _FakeFacts extends Fake implements BeaconFactCardRepositoryPort {
  BeaconFactRoomAccess access = BeaconFactRoomAccess(
    beaconStatus: BeaconStatus.open.smallintValue,
    canUseRoom: true,
    canReadContent: true,
    exists: true,
  );

  List<BeaconFactHistoryEntry> rows = const [];

  int loadRoomAccessCalls = 0;
  final historyCalls = <_HistoryCall>[];

  @override
  Future<BeaconFactRoomAccess> loadRoomAccess({
    required String beaconId,
    required String userId,
  }) async {
    loadRoomAccessCalls++;
    return access;
  }

  @override
  Future<List<BeaconFactHistoryEntry>> history({
    required String factCardId,
    ({DateTime createdAt, String entryKey})? before,
    int limit = kFactHistoryPageSize,
  }) async {
    historyCalls.add((factCardId: factCardId, before: before, limit: limit));
    return rows;
  }
}

/// Keyset paging like the repository: rows are `(created_at, entry_key)` DESC
/// and [before] is the exclusive cursor of the last entry already shown.
class _KeysetPagingFakeFacts extends _FakeFacts {
  List<BeaconFactHistoryEntry> catalog = const [];

  @override
  Future<List<BeaconFactHistoryEntry>> history({
    required String factCardId,
    ({DateTime createdAt, String entryKey})? before,
    int limit = kFactHistoryPageSize,
  }) async {
    historyCalls.add((factCardId: factCardId, before: before, limit: limit));
    final eligible = catalog.where((entry) {
      if (before == null) return true;
      final key = historySortKey(entry);
      final cursor = (
        createdAt: before.createdAt.toUtc(),
        entryKey: before.entryKey,
      );
      return historyTupleCompare(key, cursor) < 0;
    });
    return eligible.take(limit + 1).toList();
  }
}

/// Access goes through the fused `loadRoomAccess`; the legacy per-check room
/// lookups must not be used.
class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

/// Lifecycle comes from `loadRoomAccess.beaconStatus`, not a second read.
class _UnusedHierarchy extends Fake implements BeaconHierarchyRepositoryPort {}

void main() {
  late _FakeFacts facts;
  late BeaconFactCardCase case_;

  setUp(() {
    facts = _FakeFacts();
    case_ = BeaconFactCardCase(
      facts,
      _UnusedRoom(),
      _UnusedImage(),
      _UnusedTasks(),
      _UnusedHierarchy(),
      FakeBeaconAccessGuard(),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardCaseHistoryTest'),
    );
  });

  Future<({List<BeaconFactHistoryEntry> entries, String? nextCursor})>
  history({String? before}) => case_.history(
    factCardId: _factId,
    beaconId: _beaconId,
    userId: _userId,
    before: before,
  );

  group('BeaconFactCardCase.history — pagination', () {
    test(
      '51 rows from the port → 50 entries and a non-null nextCursor',
      () async {
        facts.rows = _revisionsDesc(51);
        final page = await history();

        expect(page.entries, hasLength(50));
        expect(
          (page.entries.first as BeaconFactHistoryRevision).seq,
          51,
          reason: 'newest first',
        );
        expect(
          (page.entries.last as BeaconFactHistoryRevision).seq,
          2,
          reason: 'look-ahead row (seq 1) must be trimmed off',
        );
        expect(page.nextCursor, isNotNull);
        expect(
          page.nextCursor,
          '${_at(2).toIso8601String()}|${_revisionKey(2)}',
        );
        expect(facts.historyCalls.single.limit, kFactHistoryPageSize);
      },
    );

    test('50 rows from the port → 50 entries and a null nextCursor', () async {
      facts.rows = _revisionsDesc(50);
      final page = await history();

      expect(page.entries, hasLength(50));
      expect(page.nextCursor, isNull);
      expect(facts.historyCalls.single.limit, kFactHistoryPageSize);
    });
  });

  group('BeaconFactCardCase.history — opaque cursor', () {
    test(
      "the nextCursor from one page round-trips into the next call's "
      'before',
      () async {
        facts.rows = _revisionsDesc(51);
        final page1 = await history();
        facts.historyCalls.clear();

        facts.rows = _revisionsDesc(1);
        await history(before: page1.nextCursor);

        final call = facts.historyCalls.single;
        expect(call.before, isNotNull);
        expect(call.before!.createdAt, _at(2));
        expect(call.before!.entryKey, _revisionKey(2));
      },
    );

    for (final bad in [
      'not-a-cursor',
      'not-a-date|${_revisionKey(2)}',
      'no-pipe-at-all-2026-03-01',
    ]) {
      test(
        'malformed cursor "$bad" → IdWrongException(id: factCardId) before '
        'calling history()',
        () async {
          await expectLater(
            history(before: bad),
            throwsA(
              isA<IdWrongException>().having(
                (e) => e.description,
                'description',
                'Wrong Id: [$_factId]',
              ),
            ),
          );
          expect(facts.historyCalls, isEmpty);
        },
      );
    }
  });

  group('BeaconFactCardCase.history — event page boundary (tentura-1z0)', () {
    late _KeysetPagingFakeFacts pagingFacts;
    late BeaconFactCardCase pagingCase;

    setUp(() {
      pagingFacts = _KeysetPagingFakeFacts();
      pagingFacts.catalog = _eventBoundaryCatalog();
      pagingCase = BeaconFactCardCase(
        pagingFacts,
        _UnusedRoom(),
        _UnusedImage(),
        _UnusedTasks(),
        _UnusedHierarchy(),
        FakeBeaconAccessGuard(),
        env: Env(environment: Environment.test),
        logger: Logger('BeaconFactCardCaseHistoryEventBoundaryTest'),
      );
    });

    Future<({List<BeaconFactHistoryEntry> entries, String? nextCursor})>
    pagingHistory({String? before}) => pagingCase.history(
      factCardId: _factId,
      beaconId: _beaconId,
      userId: _userId,
      before: before,
    );

    test(
      'event page boundary emits a cursor for that event and paging continues '
      'without skipping or duplicating entries',
      () async {
        final catalog = _eventBoundaryCatalog();
        final expectedDescriptions = catalog.map(_describeEntry);

        final page1 = await pagingHistory();
        expect(page1.entries, hasLength(kFactHistoryPageSize));
        final boundary = page1.entries.last;
        expect(boundary, isA<BeaconFactHistoryEvent>());
        expect(page1.nextCursor, isNotNull);

        final cursor = _parseOpaqueCursor(page1.nextCursor!);
        expect(cursor.createdAt, boundary.createdAt.toUtc());
        expect(cursor.entryKey, 'e$_boundaryActivityEventId');
        expect(
          historyEntryKeyFromEntityOnly(boundary),
          cursor.entryKey,
          reason: 'cursor must use e||id from the entity, not a test-only key',
        );

        final page2 = await pagingHistory(before: page1.nextCursor);
        final seen = [
          ...page1.entries.map(_describeEntry),
          ...page2.entries.map(_describeEntry),
        ];

        expect(seen, expectedDescriptions);
        expect(seen.toSet(), hasLength(seen.length), reason: 'no duplicates');
        expect(
          page2.entries.any((e) => identical(e, boundary)),
          isFalse,
          reason: 'boundary event must be excluded after its cursor',
        );
        for (final entry in page2.entries) {
          expect(
            historyTupleCompare(historySortKey(entry), historySortKey(boundary)),
            lessThan(0),
            reason: 'page 2 rows must sort strictly older than the boundary',
          );
        }
        expect(
          (page2.entries.first as BeaconFactHistoryRevision).seq,
          2,
          reason: 'page 2 must start immediately after the boundary event',
        );
        expect(page2.nextCursor, isNull);
      },
    );

    test(
      'nextCursor from an event page boundary round-trips to the same '
      'timestamp and entry key and returns the correct following page',
      () async {
        final page1 = await pagingHistory();
        final boundary = page1.entries.last;
        pagingFacts.historyCalls.clear();

        final page2 = await pagingHistory(before: page1.nextCursor);

        final call = pagingFacts.historyCalls.single;
        final parsed = _parseOpaqueCursor(page1.nextCursor!);
        expect(call.before, isNotNull);
        expect(call.before!.createdAt.toUtc(), parsed.createdAt);
        expect(call.before!.entryKey, parsed.entryKey);
        expect(parsed.createdAt, boundary.createdAt.toUtc());
        expect(parsed.entryKey, 'e$_boundaryActivityEventId');
        expect(historyEntryKeyFromEntityOnly(boundary), parsed.entryKey);

        expect(page2.entries, hasLength(2));
        expect(
          page2.entries.map(_describeEntry).toList(),
          ['revision:2', 'revision:1'],
        );
        expect(page2.nextCursor, isNull);
      },
    );

    test(
      'wrong event entry_key at the boundary timestamp does not return the '
      'correct older tail',
      () async {
        final page1 = await pagingHistory();
        final boundary = page1.entries.last as BeaconFactHistoryEvent;
        final correctPage2 = await pagingHistory(before: page1.nextCursor);

        final wrongCursor =
            '${boundary.createdAt.toUtc().toIso8601String()}|eNOT$_boundaryActivityEventId';
        final wrongPage = await pagingHistory(before: wrongCursor);

        expect(
          wrongPage.entries.map(_describeEntry).toList(),
          isNot(correctPage2.entries.map(_describeEntry).toList()),
          reason: 'an incorrect e||id cursor must not page past the boundary',
        );
        expect(
          wrongPage.entries.any((e) => identical(e, boundary)),
          isTrue,
          reason: 'wrong key leaves the boundary event in the result set',
        );
      },
    );
  });

  group('BeaconFactCardCase.history — D1 preflight', () {
    test(
      '!canUseRoom → UnauthorizedException(Room access required), after '
      'running the fused loadRoomAccess preflight',
      () async {
        facts.access = facts.access.copyWith(canUseRoom: false);
        await expectLater(
          history(),
          throwsA(
            isA<UnauthorizedException>().having(
              (e) => e.description,
              'description',
              'Room access required',
            ),
          ),
        );
        expect(facts.loadRoomAccessCalls, 1);
        expect(facts.historyCalls, isEmpty);
      },
    );

    test(
      'canReadContent alone does not grant access — D1 gates on canUseRoom '
      "(members only), unlike list()'s canReadContent",
      () async {
        facts.access = facts.access.copyWith(
          canUseRoom: true,
          canReadContent: false,
        );
        facts.rows = _revisionsDesc(3);

        final page = await history();

        expect(page.entries, hasLength(3));
        expect(facts.loadRoomAccessCalls, 1);
        expect(facts.historyCalls, hasLength(1));
      },
    );
  });
}
