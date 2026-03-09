import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';

part 'account_entity.freezed.dart';

@freezed
abstract class AccountEntity with _$AccountEntity {
  const factory AccountEntity({
    required String id,
    @Default('') String title,
    DateTime? fcmTokenUpdatedAt,
    ImageEntity? image,
  }) = _AccountEntity;

  const AccountEntity._();

  bool get hasAvatar => image != null && image!.id.isNotEmpty;

  String get avatarUrl => hasAvatar
      ? '$kImageServer/$kImagesPath/$id/${image!.id}.$kImageExt'
      : kAvatarPlaceholderUrl;
}
