import 'package:tentura_root/domain/entity/localizable.dart';

final class DebugFcmTestSentMessage extends LocalizableMessage {
  const DebugFcmTestSentMessage({
    required this.sent,
    required this.devices,
  });

  final int sent;
  final int devices;

  @override
  String get toEn => 'Sent to $sent of $devices device(s)';

  @override
  String get toRu => 'Отправлено на $sent из $devices устройств';
}

final class DebugFcmTestNoDevicesMessage extends LocalizableMessage {
  const DebugFcmTestNoDevicesMessage();

  @override
  String get toEn => 'No registered devices';

  @override
  String get toRu => 'Нет зарегистрированных устройств';
}

final class DebugFcmTestRateLimitedMessage extends LocalizableMessage {
  const DebugFcmTestRateLimitedMessage();

  @override
  String get toEn =>
      'Please wait 10 seconds before sending another test notification';

  @override
  String get toRu =>
      'Подождите 10 секунд перед повторной тестовой push-рассылкой';
}

final class DebugFcmTestMockMessage extends LocalizableMessage {
  const DebugFcmTestMockMessage();

  @override
  String get toEn => 'Server FCM not configured (mock mode)';

  @override
  String get toRu => 'FCM на сервере не настроен (режим mock)';
}

final class DebugEmailTestSentMessage extends LocalizableMessage {
  const DebugEmailTestSentMessage();

  @override
  String get toEn => 'Test email sent';

  @override
  String get toRu => 'Тестовое письмо отправлено';
}

final class DebugEmailTestNoEmailMessage extends LocalizableMessage {
  const DebugEmailTestNoEmailMessage();

  @override
  String get toEn => 'No verified email on this account';

  @override
  String get toRu => 'Нет подтверждённой почты в этом аккаунте';
}

final class DebugEmailTestRateLimitedMessage extends LocalizableMessage {
  const DebugEmailTestRateLimitedMessage();

  @override
  String get toEn => 'Please wait 10 seconds before sending another test email';

  @override
  String get toRu => 'Подождите 10 секунд перед повторной тестовой рассылкой';
}

final class DebugEmailTestMockMessage extends LocalizableMessage {
  const DebugEmailTestMockMessage();

  @override
  String get toEn => 'Server email not configured';

  @override
  String get toRu => 'Почта на сервере не настроена';
}

final class DebugEmailTestFailedMessage extends LocalizableMessage {
  const DebugEmailTestFailedMessage();

  @override
  String get toEn => 'Failed to send test email';

  @override
  String get toRu => 'Не удалось отправить тестовое письмо';
}
