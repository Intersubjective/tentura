class InviteAcceptedNotificationIntent {
  const InviteAcceptedNotificationIntent({
    required this.inviterUserId,
    required this.accepterUserId,
    required this.accepterDisplayName,
    required this.actionUrl,
  });

  final String inviterUserId;
  final String accepterUserId;
  final String accepterDisplayName;
  final String actionUrl;
}

