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

  /// Sentry / logs use [Object.toString]; without this they show
  /// `Instance of 'RemoteApiException'` instead of [toEn].
  @override
  String toString() => toEn;
}

abstract class LocalizableMessage extends Localizable implements Exception {
  const LocalizableMessage();
}
