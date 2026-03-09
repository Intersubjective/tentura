import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/utils/id.dart';

import '../enum.dart';
import 'image_entity.dart';

part 'user_entity.freezed.dart';

@freezed
abstract class UserEntity with _$UserEntity {
  static String get newId => generateId('U');

  const factory UserEntity({
    required String id,
    @Default('') String publicKey,
    @Default('') String title,
    @Default('') String description,
    Set<UserPrivileges>? privileges,
    ImageEntity? image,
  }) = _UserEntity;

  const UserEntity._();

  bool get hasImage => image != null;

  Map<String, Object> get asJson => {'id': id};

  String get imageUrl => hasImage
      ? '$kImageServer/$kImagesPath/$id/${image!.id}.$kImageExt'
      : kAvatarPlaceholderUrl;

  bool hasPrivilege(UserPrivileges value) =>
      privileges?.contains(value) ?? false;
}
