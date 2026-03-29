import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/enums.dart';

part 'peer_presence_entity.freezed.dart';

@freezed
abstract class PeerPresenceEntity with _$PeerPresenceEntity {
  const factory PeerPresenceEntity({
    required String userId,
    required UserPresenceStatus status,
    required DateTime lastSeenAt,
  }) = _PeerPresenceEntity;

  const PeerPresenceEntity._();
}
