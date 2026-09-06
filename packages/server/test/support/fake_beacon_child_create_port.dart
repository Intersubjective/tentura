import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/port/beacon_child_create_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';

/// No-op child-create delegate for unit tests that do not exercise nesting.
class FakeBeaconChildCreatePort implements BeaconChildCreatePort {
  Future<BeaconEntity> Function()? onPublishDraft;

  @override
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
  }) =>
      throw UnimplementedError();

  @override
  Future<BeaconEntity> publishDraft({
    required String actorUserId,
    required String childBeaconId,
  }) {
    final handler = onPublishDraft;
    if (handler == null) {
      throw UnimplementedError('FakeBeaconChildCreatePort.publishDraft');
    }
    return handler();
  }
}
