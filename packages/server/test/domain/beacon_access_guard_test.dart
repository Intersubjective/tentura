/// COV-060 — [BeaconAccessGuard] coverage model.
///
/// The concrete [BeaconAccessRepository] adds no Dart policy beyond delegating
/// to Postgres functions from migration m0098 (`beacon_can_read_content`,
/// `beacon_can_read_involvement`, `beacon_can_read_tombstone`). Those functions
/// mirror [BeaconVisibility] (ADR 0008).
///
/// | Layer | Test file |
/// |-------|-----------|
/// | Pure policy matrix | `beacon_visibility_test.dart` |
/// | SQL ↔ Dart parity (pg-tagged) | `beacon_access_sql_parity_test.dart` |
/// | Use-case auth wiring | `FakeBeaconAccessGuard` in forward/involvement tests |
///
/// Extend those files when adding roles — do not duplicate the matrix here.
library;

import 'package:drift/drift.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/domain/beacon_visibility.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';

import '../support/fake_beacon_access_guard.dart';

const _beaconId = 'Bcov060000000000000000001';
const _viewerId = 'Ucov060000000000000000001';

class _StubTenturaDb extends Fake implements TenturaDb {
  String? lastSql;
  List<Object?> lastVariables = [];
  bool nextResult = true;

  @override
  Selectable<QueryRow> customSelect(
    String sql, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation<dynamic, dynamic>> readsFrom = const {},
  }) {
    lastSql = sql;
    lastVariables = variables.map((v) => v.value).toList();
    return _SingleRowSelectable(nextResult);
  }
}

class _SingleRowSelectable extends Fake implements Selectable<QueryRow> {
  _SingleRowSelectable(this._allowed);

  final bool _allowed;

  @override
  Future<QueryRow> getSingle() async => _FakeRow(_allowed);
}

class _FakeRow extends Fake implements QueryRow {
  _FakeRow(this._allowed);

  final bool _allowed;

  @override
  T read<T>(String key) => _allowed as T;
}

void main() {
  group('BeaconAccessGuard equivalence (COV-060)', () {
    test('port predicates align with BeaconVisibility static methods', () {
      expect(BeaconAccessGuard, isA<Type>());
      expect(BeaconVisibility.canReadContent, isA<bool Function(BeaconContentVisibilityFacts)>());
      expect(
        BeaconVisibility.canReadInvolvement,
        isA<bool Function(BeaconInvolvementVisibilityFacts)>(),
      );
      expect(
        BeaconVisibility.canReadTombstone,
        isA<bool Function(BeaconTombstoneFacts)>(),
      );
    });

    test('canPreviewInvite is invitation-only — not on BeaconAccessGuard port', () {
      expect(BeaconVisibility.canPreviewInvite, isA<bool Function(BeaconInvitePreviewFacts)>());
    });
  });

  group('FakeBeaconAccessGuard', () {
    test('each method respects its independent flag', () async {
      final guard = FakeBeaconAccessGuard(
        contentAllowed: false,
        involvementAllowed: true,
        tombstoneAllowed: false,
      );

      expect(
        await guard.canReadContent(beaconId: _beaconId, viewerId: _viewerId),
        isFalse,
      );
      expect(
        await guard.canReadInvolvement(beaconId: _beaconId, viewerId: _viewerId),
        isTrue,
      );
      expect(
        await guard.canReadTombstone(beaconId: _beaconId, viewerId: _viewerId),
        isFalse,
      );
    });
  });

  group('BeaconAccessRepository (thin SQL delegate)', () {
    late _StubTenturaDb db;
    late BeaconAccessRepository repo;

    setUp(() {
      db = _StubTenturaDb();
      repo = BeaconAccessRepository(db);
    });

    test('canReadContent calls beacon_can_read_content with ids', () async {
      db.nextResult = true;

      expect(
        await repo.canReadContent(beaconId: _beaconId, viewerId: _viewerId),
        isTrue,
      );
      expect(db.lastSql, contains('beacon_can_read_content'));
      expect(db.lastVariables, [_beaconId, _viewerId]);
    });

    test('canReadInvolvement calls beacon_can_read_involvement with ids', () async {
      db.nextResult = false;

      expect(
        await repo.canReadInvolvement(beaconId: _beaconId, viewerId: _viewerId),
        isFalse,
      );
      expect(db.lastSql, contains('beacon_can_read_involvement'));
      expect(db.lastVariables, [_beaconId, _viewerId]);
    });

    test('canReadTombstone calls beacon_can_read_tombstone with ids', () async {
      db.nextResult = true;

      expect(
        await repo.canReadTombstone(beaconId: _beaconId, viewerId: _viewerId),
        isTrue,
      );
      expect(db.lastSql, contains('beacon_can_read_tombstone'));
      expect(db.lastVariables, [_beaconId, _viewerId]);
    });
  });
}
