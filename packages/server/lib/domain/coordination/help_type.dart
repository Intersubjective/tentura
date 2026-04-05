/// Allowed optional `help_type` keys on `beacon_commitment` (Phase 1).
const kAllowedHelpTypeKeys = <String>{
  'money',
  'time',
  'skill',
  'verification',
  'contact',
  'transport',
  'other',
};

bool isAllowedHelpType(String? helpType) =>
    helpType == null || helpType.isEmpty || kAllowedHelpTypeKeys.contains(helpType);
