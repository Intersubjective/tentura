import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';

abstract interface class InviteAcceptedNotificationPort {
  Future<void> notifyInviteAccepted(InviteAcceptedNotificationIntent intent);
}

