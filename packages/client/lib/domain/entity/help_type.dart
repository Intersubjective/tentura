/// Optional commit help-type keys (aligned with server `kAllowedHelpTypeKeys`).
enum CommitHelpType {
  money,
  time,
  skill,
  verification,
  contact,
  transport,
  other;

  String get wireKey => switch (this) {
        CommitHelpType.money => 'money',
        CommitHelpType.time => 'time',
        CommitHelpType.skill => 'skill',
        CommitHelpType.verification => 'verification',
        CommitHelpType.contact => 'contact',
        CommitHelpType.transport => 'transport',
        CommitHelpType.other => 'other',
      };

  static CommitHelpType? tryParse(String? key) => switch (key) {
        'money' => CommitHelpType.money,
        'time' => CommitHelpType.time,
        'skill' => CommitHelpType.skill,
        'verification' => CommitHelpType.verification,
        'contact' => CommitHelpType.contact,
        'transport' => CommitHelpType.transport,
        'other' => CommitHelpType.other,
        _ => null,
      };
}
