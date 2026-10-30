import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_access_guard.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: BeaconAccessGuard)
class BeaconAccessRepository implements BeaconAccessGuard {
  BeaconAccessRepository(this._db);

  final TenturaDb _db;

  @override
  Future<bool> canReadContent({
    required String beaconId,
    required String viewerId,
  }) =>
      _callPredicate('beacon_can_read_content', beaconId, viewerId);

  @override
  Future<Set<String>> readableContentIds({
    required Iterable<String> beaconIds,
    required String viewerId,
  }) async {
    final ids = beaconIds.toSet().toList();
    if (ids.isEmpty) return {};
    final rows = await _db
        .customSelect(
          r'SELECT id FROM unnest($1::text[]) AS id '
          r'WHERE public.beacon_can_read_content(id, $2)',
          variables: [
            Variable<List<String>>(ids, PgTypes.textArray),
            Variable<String>(viewerId),
          ],
        )
        .get();
    return {for (final row in rows) row.read<String>('id')};
  }

  @override
  Future<bool> canReadInvolvement({
    required String beaconId,
    required String viewerId,
  }) =>
      _callPredicate('beacon_can_read_involvement', beaconId, viewerId);

  @override
  Future<bool> canReadTombstone({
    required String beaconId,
    required String viewerId,
  }) =>
      _callPredicate('beacon_can_read_tombstone', beaconId, viewerId);

  Future<bool> _callPredicate(
    String functionName,
    String beaconId,
    String viewerId,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT public.$functionName(\$1, \$2) AS allowed',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(viewerId),
          ],
        )
        .getSingle();
    return row.read<bool>('allowed');
  }
}
