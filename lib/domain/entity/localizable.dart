abstract class Localizable {
  const Localizable();

  String get toRu;

  String get toEn;

  String toL10n(String? locale) => switch (locale) {
    'ru' => toRu,
    'en' => toEn,
    _ => 'Unsupported locale for $runtimeType',
  };
}

abstract class LocalizableException extends Localizable implements Exception {
  const LocalizableException();
}

abstract class LocalizableMessage extends Localizable implements Exception {
  const LocalizableMessage();
}
