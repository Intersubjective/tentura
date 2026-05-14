/// Required withdraw reason tag keys (`beacon_help_offer.withdraw_reason`).
const kAllowedWithdrawReasonKeys = <String>{
  'cannot_do_it',
  'timing',
  'wrong_fit',
  'someone_else',
  'other',
};

bool isAllowedWithdrawReason(String? reason) =>
    reason != null &&
    reason.isNotEmpty &&
    kAllowedWithdrawReasonKeys.contains(reason);
