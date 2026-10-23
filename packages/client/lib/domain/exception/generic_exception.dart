import 'package:tentura_root/domain/entity/localizable.dart';

import 'server_error_copy.dart';

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
/// localized: a [code] listed in [kServerErrorCopy] shows plain words in the
/// locale instead (#683), any other shows the server's text in both.
final class RemoteApiException extends GenericException {
  const RemoteApiException(this.message, {this.code});

  /// The server's own text. Kept for logs and "Copy details" even when the
  /// person is shown [toEn] / [toRu].
  final String message;

  /// The server's error code (`extensions.code`), when it sent one.
  final String? code;

  /// Plain copy replaces the server's [message] for this [code].
  bool get hasPlainCopy => serverErrorCopyFor(code) != null;

  @override
  String get toEn => serverErrorCopyFor(code)?.en ?? message;

  @override
  String get toRu => serverErrorCopyFor(code)?.ru ?? message;

  /// The server's text, as before: logs, Sentry and the callers that match
  /// on it read this, not the plain copy.
  @override
  String toString() => message;
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
