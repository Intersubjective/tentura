import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';

/// Nested child create/publish command surface for [BeaconCase] delegation.
abstract class BeaconChildCreatePort {
  Future<BeaconChildCreateResult> createChild({
    required String actorUserId,
    required String parentBeaconId,
    String? sourceMessageId,
    required String clientCommandId,
    required String title,
    String? description,
    String? context,
    String? tags,
    String? needs,
    String? primaryNeedSlug,
    bool primaryNeedSlugProvided = false,
    DateTime? endAt,
    DateTime? startAt,
    Coordinates? coordinates,
    String? addressLabel,
    required bool draft,
  });

  Future<BeaconEntity> publishDraft({
    required String actorUserId,
    required String childBeaconId,
  });
}
