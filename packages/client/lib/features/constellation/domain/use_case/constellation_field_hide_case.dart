import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../constellation_field_patches.dart';
import '../entity/constellation_field_hidden_item.dart';
import '../entity/constellation_field_target_kind.dart';
import '../port/constellation_field_hide_port.dart';
import '../port/constellation_targeted_read_port.dart';
import 'constellation_field_store_case.dart';

@lazySingleton
final class ConstellationFieldHideCase extends UseCaseBase {
  ConstellationFieldHideCase(
    this._port,
    this._store,
    this._targetedReads, {
    required super.env,
    required super.logger,
  });

  final ConstellationFieldHidePort _port;
  final ConstellationFieldStoreCase _store;
  final ConstellationTargetedReadPort _targetedReads;

  Future<void> hide({
    required int targetKind,
    required String targetId,
  }) =>
      _port.hide(targetKind: targetKind, targetId: targetId);

  Future<void> unhide({
    required int targetKind,
    required String targetId,
  }) =>
      _port.unhide(targetKind: targetKind, targetId: targetId);

  Future<List<ConstellationFieldHiddenItem>> fetchHiddenItems({
    String? cursor,
  }) =>
      _port.fetchHiddenItems(cursor: cursor);

  /// Restores a hidden item on the loaded field, then calls `fieldUnhide`.
  Future<void> showHiddenItemOnField(ConstellationFieldHiddenItem item) async {
    final beaconId = item.targetId;
    final snapshot = _store.takeRestorableHideSnapshot(beaconId);
    if (snapshot != null) {
      _store.restoreFieldHide(snapshot);
    } else {
      await _restoreHiddenWithoutSnapshot(item);
    }
    try {
      await _port.unhide(
        targetKind: item.targetKind.wireValue,
        targetId: beaconId,
      );
    } on Object {
      if (snapshot != null) {
        _store.applyFieldHide(beaconId);
      }
      rethrow;
    }
  }

  Future<void> _restoreHiddenWithoutSnapshot(
    ConstellationFieldHiddenItem item,
  ) async {
    if (item.targetKind != ConstellationFieldTargetKind.request) {
      return;
    }
    final field = _store.current.field;
    if (field == null) {
      return;
    }
    final mark = _store.readMark();
    final requests = await _targetedReads.fetchRequests(
      {item.targetId},
      membershipFilters: _store.projectionParams.membershipFilters,
    );
    _store.addRequests(
      [
        for (final request in requests)
          if (request.isMine ||
              constellationFieldHasVisiblePerson(field, request.authorId))
            request,
      ],
      mark,
    );
  }
}
