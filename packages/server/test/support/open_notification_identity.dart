import 'package:tentura_server/domain/notification/notification_identity.dart';

/// Every entity readable as a Request labelled [label]; no actor hidden.
class OpenNotificationIdentity implements NotificationIdentityPort {
  const OpenNotificationIdentity({this.label = 'Title', this.actorName});

  final String label;
  final String? actorName;

  @override
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> requests,
  ) async => [
    for (final _ in requests)
      NotificationIdentity(
        entityKind: NotificationEntityKind.request,
        label: label,
        tombstone: false,
        readable: true,
        actorName: actorName,
        actorHidden: false,
        relatedLabel: null,
        expired: false,
      ),
  ];
}
