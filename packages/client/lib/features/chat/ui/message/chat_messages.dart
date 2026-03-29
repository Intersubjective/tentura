import 'package:tentura_root/domain/entity/localizable.dart';

/// Shown when the user tries to open chat with a friend who has no trust path
/// toward the current user (rScore == 0).
final class NoTrustPathForChatMessage extends LocalizableMessage {
  const NoTrustPathForChatMessage();

  @override
  String get toEn =>
      "This user can't see you because there is no trust path from them to you, "
      "so you can't message them";

  @override
  String get toRu =>
      'Этот пользователь вас не видит: от него к вам нет пути доверия, '
      'поэтому вы не можете написать ему.';
}
