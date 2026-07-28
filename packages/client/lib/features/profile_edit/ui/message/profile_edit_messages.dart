import 'package:tentura_root/domain/entity/localizable.dart';

/// Shown after avatar pick/crop stages bytes; profile still needs AppBar Save.
final class ProfileAvatarReadyMessage extends LocalizableMessage {
  const ProfileAvatarReadyMessage();

  @override
  String get toEn =>
      'Photo ready — tap Save to update your profile.';

  @override
  String get toRu =>
      'Фото готово — нажмите «Сохранить», чтобы обновить профиль.';
}
