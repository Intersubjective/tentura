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
