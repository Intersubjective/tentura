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

/// Partial or zero delivery when one person was skipped for availability.
final class ForwardPartialDeliveryMessage extends LocalizableMessage {
  const ForwardPartialDeliveryMessage({
    required this.deliveredCount,
    required this.requestedCount,
    required this.skippedName,
  });

  final int deliveredCount;
  final int requestedCount;
  final String skippedName;

  @override
  String get toEn =>
      'Delivered to $deliveredCount of $requestedCount — $skippedName isn\'t taking new requests right now.';

  @override
  String get toRu =>
      'Отправлено $deliveredCount из $requestedCount — $skippedName сейчас не принимает новые запросы.';
}

/// Partial or zero delivery when two or more people were skipped for availability.
final class ForwardPartialDeliveryManyMessage extends LocalizableMessage {
  const ForwardPartialDeliveryManyMessage({
    required this.deliveredCount,
    required this.requestedCount,
    required this.skippedCount,
  });

  final int deliveredCount;
  final int requestedCount;
  final int skippedCount;

  @override
  String get toEn =>
      'Delivered to $deliveredCount of $requestedCount — $skippedCount people aren\'t taking new requests right now.';

  @override
  String get toRu =>
      'Отправлено $deliveredCount из $requestedCount — $skippedCount получателей сейчас не принимают новые запросы.';
}

/// Embedded beacon-create confirmation: delivered count against requested denominator.
final class ForwardDeliveredOfMessage extends LocalizableMessage {
  const ForwardDeliveredOfMessage({
    required this.deliveredCount,
    required this.requestedCount,
  });

  final int deliveredCount;
  final int requestedCount;

  @override
  String get toEn {
    if (deliveredCount == 1 && requestedCount == 1) {
      return 'Delivered to 1 of 1 person';
    }
    return 'Delivered to $deliveredCount of $requestedCount people';
  }

  @override
  String get toRu {
    if (deliveredCount == 1 && requestedCount == 1) {
      return 'Доставлено 1 из 1 человека';
    }
    return 'Доставлено $deliveredCount из $requestedCount людей';
  }
}
