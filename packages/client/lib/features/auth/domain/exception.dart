import 'package:tentura_root/domain/entity/localizable.dart';

///
sealed class AuthException extends LocalizableException {
  const AuthException();

  @override
  String get toEn => 'Auth error:';

  @override
  String get toRu => 'Ошибка авторизации:';
}

///
final class AuthUnknownException extends AuthException {
  const AuthUnknownException();

  @override
  String get toEn => '${super.toEn} unknown error!';

  @override
  String get toRu => '${super.toRu} неизвестная ошибка!';
}

///
class AuthSeedExistsException extends AuthException {
  const AuthSeedExistsException();

  @override
  String get toEn => '${super.toEn} seed already exists!';

  @override
  String get toRu => '${super.toRu} seed-фраза уже существует!';
}

///
class AuthSeedIsWrongException extends AuthException {
  const AuthSeedIsWrongException();

  @override
  String get toEn =>
      "That seed doesn't match an account. Check for missing characters.";

  @override
  String get toRu =>
      'Этот seed не подходит ни к одному аккаунту. '
      'Проверьте, не пропущены ли символы.';
}

///
class AuthIdIsWrongException extends AuthException {
  const AuthIdIsWrongException();

  @override
  String get toEn => '${super.toEn} account ID is wrong!';

  @override
  String get toRu => '${super.toRu} неверный ID аккаунта!';
}

///
class AuthIdNotFoundException extends AuthException {
  const AuthIdNotFoundException();

  @override
  String get toEn => '${super.toEn} account ID not found!';

  @override
  String get toRu => '${super.toRu} аккаунт не найден!';
}

///
class InvitationCodeIsWrongException extends AuthException {
  const InvitationCodeIsWrongException();

  @override
  String get toEn => '${super.toEn} Invitation Code is wrong!';

  @override
  String get toRu => '${super.toRu} неверный код приглашения!';
}

/// HttpOnly browser session was present but rejected by the server (401/403).
final class SessionAuthRejectedException extends AuthException {
  const SessionAuthRejectedException();

  @override
  String get toEn => '${super.toEn} session expired or invalid';

  @override
  String get toRu => '${super.toRu} сессия истекла или недействительна';
}

/// The browser cookie belongs to someone other than the selected account.
final class SessionAccountMismatchException extends AuthException {
  const SessionAccountMismatchException(this.displayName);

  final String displayName;

  @override
  String get toEn => 'Sign in again as $displayName';

  @override
  String get toRu => 'Войдите снова как $displayName';
}

/// Authenticated API call failed because the session or bearer token is gone.
final class AuthSessionLostException extends AuthException {
  const AuthSessionLostException();

  @override
  String get toEn => "We couldn't verify your session";

  @override
  String get toRu => 'Не удалось проверить вашу сессию';
}

/// Another tab replaced the shared cookie with a different account's session.
final class AuthSessionAccountChangedException extends AuthException {
  const AuthSessionAccountChangedException();

  @override
  String get toEn => 'Your account changed in another tab. Reloading…';

  @override
  String get toRu => 'Аккаунт изменён в другой вкладке. Перезагружаем…';
}

/// Session could not be verified because the server was slow or unreachable
/// (timeout, 5xx, network). Not a rejection: the session may still be valid,
/// so callers retry instead of signing the user out.
final class AuthServerUnavailableException extends AuthException {
  const AuthServerUnavailableException({this.isReported = false});

  /// Whether seed-recovery telemetry has already captured the underlying error.
  final bool isReported;

  @override
  String get toEn => "We couldn't reach the server to verify your session";

  @override
  String get toRu => 'Не удалось связаться с сервером для проверки сессии';
}
