import 'package:tentura_root/domain/entity/localizable.dart';

final class PersonForwardSentMessage extends LocalizableMessage {
  const PersonForwardSentMessage(this.name);

  final String name;

  @override
  String get toEn => 'Request sent to $name';

  @override
  String get toRu => 'Запрос отправлен: $name';
}

final class PersonForwardAvailabilitySkippedMessage extends LocalizableMessage {
  const PersonForwardAvailabilitySkippedMessage(this.name);

  final String name;

  @override
  String get toEn => '$name isn\'t taking new requests right now.';

  @override
  String get toRu => '$name сейчас не принимает новые запросы.';
}
