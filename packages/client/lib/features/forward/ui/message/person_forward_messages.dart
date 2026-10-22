import 'package:tentura_root/domain/entity/localizable.dart';

final class PersonForwardSentMessage extends LocalizableMessage {
  const PersonForwardSentMessage(this.name, {this.isPost = false});

  final String name;

  /// The sent beacon is a Post, not a request (#501).
  final bool isPost;

  @override
  String get toEn => isPost ? 'Post sent to $name' : 'Request sent to $name';

  @override
  String get toRu =>
      isPost ? 'Пост отправлен: $name' : 'Запрос отправлен: $name';
}

final class PersonForwardAvailabilitySkippedMessage extends LocalizableMessage {
  const PersonForwardAvailabilitySkippedMessage(this.name);

  final String name;

  @override
  String get toEn => "$name isn't taking new requests right now.";

  @override
  String get toRu => '$name сейчас не принимает новые запросы.';
}
