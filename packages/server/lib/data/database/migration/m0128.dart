part of '_migrations.dart';

/// Drop the dead `digested_at` column: no digest feature ever shipped that
/// reads or writes it, and no index or constraint references it.
final m0128 = Migration('0128', [
  r'''ALTER TABLE public.notification_outbox DROP COLUMN digested_at;''',
]);
