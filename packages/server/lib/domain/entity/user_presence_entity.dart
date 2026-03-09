import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/enums.dart';

part 'user_presence_entity.freezed.dart';

@freezed
abstract class UserPresenceEntity with _$UserPresenceEntity {
  const factory UserPresenceEntity({
    required String userId,
    required DateTime lastSeenAt,
    required DateTime lastNotifiedAt,
    required Duration offlineAfterDelay,
    required UserPresenceStatus status,
  }) = _UserPresenceEntity;

  const UserPresenceEntity._();

  bool get hasNotified => lastNotifiedAt.isAfter(lastSeenAt);

  bool get shouldNotify =>
      !hasNotified ||
      status != UserPresenceStatus.online ||
      lastSeenAt.isAfter(DateTime.timestamp().add(offlineAfterDelay));
}
