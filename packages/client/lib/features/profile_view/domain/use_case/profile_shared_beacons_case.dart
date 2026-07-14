import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/profile_shared_beacons_repository.dart';

/// Owns the live invalidation routes for the profile's shared-Request section.
@injectable
final class ProfileSharedBeaconsCase extends UseCaseBase {
  ProfileSharedBeaconsCase(
    this._repository,
    this._realtime, {
    required super.env,
    required super.logger,
  });

  final ProfileSharedBeaconsRepository _repository;
  final RealtimeSyncCase _realtime;

  Stream<void> get projectionChanges => MergeStream<void>([
    _realtime
        .changesFor(const {
          RealtimeEntityKind.beacon,
          RealtimeEntityKind.forward,
          RealtimeEntityKind.helpOffer,
        })
        .map((_) {}),
    _realtime.catchUps.map((_) {}),
  ]);

  Future<ProfileSharedBeaconsData> load({
    required String meId,
    required String targetId,
  }) => _repository.fetch(meId: meId, targetId: targetId);
}
