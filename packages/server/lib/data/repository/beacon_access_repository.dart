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

  @override
  Future<bool> canReadLinkedDetail({
    required String beaconId,
    required String viewerId,
  }) async {
    // Task 03 wires `beacon_can_read_linked_detail` SQL parity.
    return false;
  }

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
