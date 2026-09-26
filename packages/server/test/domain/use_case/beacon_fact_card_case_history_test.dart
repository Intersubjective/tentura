import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/beacon_fact_history_entry_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

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

/// Access goes through the fused `loadRoomAccess`; the legacy per-check room
/// lookups must not be used.
class _UnusedRoom extends Fake implements BeaconRoomRepositoryPort {}

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
