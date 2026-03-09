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
  String get toEn => '${super.toEn} there is no correct seed!';

  @override
  String get toRu => '${super.toRu} некорректная seed-фраза!';
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
