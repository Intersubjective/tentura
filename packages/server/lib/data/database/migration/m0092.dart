part of '_migrations.dart';

/// Coordination status redesign: remove auto-derived value 1 (was
/// helpOffersWaitingForReview); field is author-set only (0/2/3).
final m0092 = Migration('0092', [
  '''
UPDATE public.beacon SET coordination_status = 0 WHERE coordination_status = 1;
''',
  '''
COMMENT ON COLUMN public.beacon.coordination_status IS
  '0=neutral, 2=needsMoreHelp, 3=enoughHelp';
''',
]);
