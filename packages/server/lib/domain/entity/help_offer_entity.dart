import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_entity.dart';

part 'help_offer_entity.freezed.dart';

@freezed
abstract class HelpOfferEntity with _$HelpOfferEntity {
  const factory HelpOfferEntity({
    required String beaconId,
    required String userId,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default('') String message,
    @Default(0) int status,
    String? helpType,
    String? withdrawReason,
    UserEntity? user,
  }) = _HelpOfferEntity;

  const HelpOfferEntity._();

  bool get isActive => status == 0;
  bool get isWithdrawn => status == 1;
}
