/// Required uncommit reason tag keys (`beacon_commitment.uncommit_reason`).
const kAllowedUncommitReasonKeys = <String>{
  'cannot_do_it',
  'timing',
  'wrong_fit',
  'someone_else',
  'other',
};

bool isAllowedUncommitReason(String? reason) =>
    reason != null &&
    reason.isNotEmpty &&
    kAllowedUncommitReasonKeys.contains(reason);
