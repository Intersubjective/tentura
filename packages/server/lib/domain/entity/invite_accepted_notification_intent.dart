class InviteAcceptedNotificationIntent {
  const InviteAcceptedNotificationIntent({
    required this.inviterUserId,
    required this.accepterUserId,
    required this.accepterDisplayName,
    required this.actionUrl,
    required this.inviteOrigin,
    this.accepterHandle = '',
  });

  final String inviterUserId;
  final String accepterUserId;
  final String accepterDisplayName;
  final String actionUrl;

  /// Wire literal: `'new_account'` or `'existing_account'`.
  final String inviteOrigin;
  final String accepterHandle;
}
