import 'package:tentura_root/domain/entity/localizable.dart';

abstract class ServerException extends LocalizableException {
  const ServerException();
}

final class ServerUnknownException extends ServerException {
  const ServerUnknownException();

  @override
  String get toEn => 'Unknown error';

  @override
  String get toRu => 'Неизвестная ошибка';
}

final class ServerNoDataException extends ServerException {
  const ServerNoDataException();

  @override
  String get toEn => 'No data';

  @override
  String get toRu => 'Нет данных';
}

/// Non-2xx response from a REST endpoint; carries the HTTP [statusCode] so
/// callers can map it to a domain exception (e.g. 404/409).
final class ServerStatusException extends ServerException {
  const ServerStatusException(this.statusCode);

  final int statusCode;

  @override
  String get toEn => 'Server error ($statusCode)';

  @override
  String get toRu => 'Ошибка сервера ($statusCode)';
}
