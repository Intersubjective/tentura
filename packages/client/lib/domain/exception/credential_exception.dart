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
