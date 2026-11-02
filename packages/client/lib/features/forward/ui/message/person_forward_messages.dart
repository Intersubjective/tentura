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

/// The server skipped the person: this sender already forwarded the beacon to
/// them (an earlier send or a concurrent one).
final class PersonForwardAlreadySentMessage extends LocalizableMessage {
  const PersonForwardAlreadySentMessage(this.name, {this.isPost = false});

  final String name;

  /// The beacon is a Post, not a request (#501).
  final bool isPost;

  @override
  String get toEn => isPost
      ? 'You already sent this Post to $name.'
      : 'You already sent this Request to $name.';

  @override
  String get toRu => isPost
      ? 'Вы уже отправили этот пост: $name.'
      : 'Вы уже отправили этот запрос: $name.';
}

/// The server skipped the person: they are blocked by or hidden from the
/// sender.
final class PersonForwardBlockedMessage extends LocalizableMessage {
  const PersonForwardBlockedMessage(this.name);

  final String name;

  @override
  String get toEn => "$name can't receive it from you.";

  @override
  String get toRu => '$name не может получить его от вас.';
}

/// The server delivered nothing and gave no reason.
final class PersonForwardNotDeliveredMessage extends LocalizableMessage {
  const PersonForwardNotDeliveredMessage(this.name);

  final String name;

  @override
  String get toEn => "Couldn't send it to $name. Try again later.";

  @override
  String get toRu => 'Не удалось отправить: $name. Попробуйте позже.';
}
