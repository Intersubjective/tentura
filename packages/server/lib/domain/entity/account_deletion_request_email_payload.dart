/// Data passed to outbound email when a user submits a profile-deletion request.
class AccountDeletionRequestEmailPayload {
  const AccountDeletionRequestEmailPayload({
    required this.complaintId,
    required this.userId,
    required this.contactEmail,
    required this.details,
    required this.requestedAt,
  });

  final String complaintId;
  final String userId;
  final String contactEmail;
  final String details;
  final DateTime requestedAt;
}
