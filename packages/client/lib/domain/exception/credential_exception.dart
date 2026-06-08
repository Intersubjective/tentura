import 'package:tentura_root/domain/entity/localizable.dart';

abstract class CredentialException extends LocalizableException {
  const CredentialException();
}

/// Server refused to remove the account's only sign-in method (HTTP 409).
final class LastCredentialException extends CredentialException {
  const LastCredentialException();

  @override
  String get toEn => "You can't remove your only sign-in method";

  @override
  String get toRu => 'Нельзя удалить единственный способ входа';
}

/// The credential to remove no longer exists (HTTP 404).
final class CredentialNotFoundException extends CredentialException {
  const CredentialNotFoundException();

  @override
  String get toEn => 'Sign-in method not found';

  @override
  String get toRu => 'Способ входа не найден';
}

/// Another account already owns this sign-in method (HTTP 409).
final class CredentialConflictException extends CredentialException {
  const CredentialConflictException();

  @override
  String get toEn =>
      'This sign-in method is already linked to another account';

  @override
  String get toRu =>
      'Этот способ входа уже привязан к другому аккаунту';
}

final class CredentialLinkedMessage extends LocalizableMessage {
  const CredentialLinkedMessage(this.method);

  final String method;

  @override
  String get toEn => switch (method) {
    'google' => 'Google linked',
    'email' => 'Email linked',
    'seed' => 'Recovery seed linked',
    _ => 'Sign-in method linked',
  };

  @override
  String get toRu => switch (method) {
    'google' => 'Google привязан',
    'email' => 'Почта привязана',
    'seed' => 'Seed восстановления привязан',
    _ => 'Способ входа привязан',
  };
}

final class CredentialEmailLinkSentMessage extends LocalizableMessage {
  const CredentialEmailLinkSentMessage();

  @override
  String get toEn => 'Check your email for a confirmation link';

  @override
  String get toRu => 'Проверьте почту — мы отправили ссылку для подтверждения';
}
