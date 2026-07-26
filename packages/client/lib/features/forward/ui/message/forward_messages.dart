import 'package:tentura_root/domain/entity/localizable.dart';

final class ForwardSentMessage extends LocalizableMessage {
  const ForwardSentMessage(this.count);

  final int count;

  @override
  String get toEn => count == 1
      ? 'Request forwarded to 1 person'
      : 'Request forwarded to $count people';

  @override
  String get toRu => count == 1
      ? 'Запрос переслан: 1 человеку'
      : 'Запрос переслан: $count людям';
}
