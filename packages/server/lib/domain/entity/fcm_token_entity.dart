import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'fcm_token_entity.freezed.dart';

@freezed
abstract class FcmTokenEntity with _$FcmTokenEntity {
  const factory FcmTokenEntity({
    required String userId,
    required UuidValue appId,
    required String platform,
    required String token,
    required DateTime createdAt,
  }) = _FcmTokenEntity;

  const FcmTokenEntity._();
}
