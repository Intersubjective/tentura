import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';

/// Field and media writes a request editor needs, in domain terms only.
abstract interface class BeaconWritePort {
  Future<Beacon> fetchBeaconById(String id);

  Future<Beacon> create(Beacon beacon, {bool draft});

  Future<Beacon> updateDraft(Beacon beacon);

  Future<Beacon> update(Beacon beacon);

  Future<void> publishDraft(String id);

  Future<void> delete(String id);

  /// Uploads [image] as an invisible stage and returns its exact server id.
  Future<String> stageImage({
    required String beaconId,
    required ImageEntity image,
  });

  /// Publishes the complete ordered media state in one locked command.
  ///
  /// [coverThumbImageId] is always sent by current clients (null clears thumb).
  Future<Beacon> setMedia({
    required String beaconId,
    required List<String> imageIds,
    required String? coverImageId,
    required String? coverThumbImageId,
    required BeaconCoverSource coverSource,
  });
}
