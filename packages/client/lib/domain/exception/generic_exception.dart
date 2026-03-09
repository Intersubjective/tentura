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
