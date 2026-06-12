import 'package:tentura_root/domain/entity/localizable.dart';

sealed class GenericException extends LocalizableException {
  const GenericException();
}

final class UnknownException extends GenericException {
  const UnknownException();

  @override
  String get toEn => 'Unknown error';

  @override
  String get toRu => 'Неизвестная ошибка';
}

final class UnknownPlatformException extends GenericException {
  const UnknownPlatformException();

  @override
  String get toEn => 'Unknown error';

  @override
  String get toRu => 'Неизвестная ошибка';
}

final class ConnectionUplinkException extends GenericException {
  const ConnectionUplinkException();

  @override
  String get toEn => 'No Internet connection';

  @override
  String get toRu => 'Нет соединения с интернетом';
}

/// An error reported by the server (GraphQL/API error with a message).
/// Unlike [ConnectionUplinkException] the server DID answer — surfacing its
/// message beats a misleading "no internet". Server messages are not
/// localized, so both locales show the same text.
final class RemoteApiException extends GenericException {
  const RemoteApiException(this.message);

  final String message;

  @override
  String get toEn => message;

  @override
  String get toRu => message;
}
