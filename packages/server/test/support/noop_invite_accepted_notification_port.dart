import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/port/invite_accepted_notification_port.dart';

class NoopInviteAcceptedNotificationPort implements InviteAcceptedNotificationPort {
  final intents = <InviteAcceptedNotificationIntent>[];

  @override
  Future<void> notifyInviteAccepted(InviteAcceptedNotificationIntent intent) async {
    intents.add(intent);
  }
}
