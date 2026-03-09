sealed class FcmMessageEntity {}

class FcmNotificationEntity implements FcmMessageEntity {
  const FcmNotificationEntity({
    required this.title,
    required this.body,
    this.actionUrl,
    this.imageUrl,
  });

  final String title;

  final String body;

  final String? imageUrl;

  final String? actionUrl;
}
