part of '_migrations.dart';

/// One-time reset: delete pre-real-user legacy receipts. Tentura has no real
/// users; these carry no compatibility obligation. Not a behavioral no-op.
final m0126 = Migration('0126', [
  r'''DELETE FROM public.notification_outbox WHERE access_policy = 'legacy';''',
]);
