import 'package:meta/meta.dart';

/// Per-recipient forward record from the current user's perspective
/// (GraphQL `MyForwardRecipient`).
@immutable
class MyForwardRecipientResult {
  const MyForwardRecipientResult({
    required this.edgeId,
    required this.recipientId,
    required this.note,
    this.readAt,
  });

  final String edgeId;
  final String recipientId;
  final String note;
  final DateTime? readAt;
}

/// V2 forward-screen involvement id sets (GraphQL `BeaconInvolvement`).
@immutable
class BeaconInvolvementResult {
  const BeaconInvolvementResult({
    required this.forwardedToIds,
    required this.helpOfferedIds,
    required this.withdrawnIds,
    required this.rejectedIds,
    required this.watchingIds,
    required this.onwardForwarderIds,
    required this.myForwardedRecipients,
  });

  final List<String> forwardedToIds;
  final List<String> helpOfferedIds;
  final List<String> withdrawnIds;
  final List<String> rejectedIds;
  final List<String> watchingIds;
  final List<String> onwardForwarderIds;
  final List<MyForwardRecipientResult> myForwardedRecipients;
}
