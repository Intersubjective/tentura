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
  const RemoteApiException(this.message, {this.code});

  final String message;

  /// The server's error code (`extensions.code`), when it sent one.
  final String? code;

  @override
  String get toEn => message;

  @override
  String get toRu => message;
}

/// Server admission backoff, preserved across the transport boundary.
final class RemoteApiRetryLaterException extends GenericException {
  const RemoteApiRetryLaterException(this.retryAfter);

  final Duration retryAfter;

  // U094: shown to people when a request is turned away for a moment;
  // plain words, no server or database names.
  @override
  String get toEn => 'Busy right now. Try again in a few seconds.';

  @override
  String get toRu => 'Сервер занят. Попробуйте ещё раз через несколько секунд.';
}
