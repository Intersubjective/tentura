/// Optional commit help-type keys (aligned with server `kAllowedHelpTypeKeys`).
enum CommitHelpType {
  money,
  time,
  verification,
  contact,
  transport,
  documents,
  physicalHelp,
  tools,
  housing,
  workspace,
  introductions,
  other;

  String get wireKey => switch (this) {
        CommitHelpType.money => 'money',
        CommitHelpType.time => 'time',
        CommitHelpType.verification => 'verification',
        CommitHelpType.contact => 'contact',
        CommitHelpType.transport => 'transport',
        CommitHelpType.documents => 'documents',
        CommitHelpType.physicalHelp => 'physical_help',
        CommitHelpType.tools => 'tools',
        CommitHelpType.housing => 'housing',
        CommitHelpType.workspace => 'workspace',
        CommitHelpType.introductions => 'introductions',
        CommitHelpType.other => 'other',
      };

  static CommitHelpType? tryParse(String? key) => switch (key) {
        'money' => CommitHelpType.money,
        'time' => CommitHelpType.time,
        'skill' => CommitHelpType.other,
        'verification' => CommitHelpType.verification,
        'contact' => CommitHelpType.contact,
        'transport' => CommitHelpType.transport,
        'documents' => CommitHelpType.documents,
        'physical_help' => CommitHelpType.physicalHelp,
        'tools' => CommitHelpType.tools,
        'housing' => CommitHelpType.housing,
        'workspace' => CommitHelpType.workspace,
        'introductions' => CommitHelpType.introductions,
        'other' => CommitHelpType.other,
        _ => null,
      };
}
