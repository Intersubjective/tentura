import 'package:tentura_root/domain/entity/localizable.dart';

final class PersonForwardSentMessage extends LocalizableMessage {
  const PersonForwardSentMessage(this.name);

  final String name;

  @override
  String get toEn => 'Request sent to $name';

  @override
  String get toRu => 'Запрос отправлен: $name';
}
