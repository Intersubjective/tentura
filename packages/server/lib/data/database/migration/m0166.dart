part of '_migrations.dart';

/// Admit `expired` as a terminal settlement kind on notification receipts.
final m0166 = Migration('0166', [
  r'''
ALTER TABLE public.notification_outbox
  DROP CONSTRAINT notification_outbox__settlement_kind_chk,
  ADD CONSTRAINT notification_outbox__settlement_kind_chk
    CHECK (settlement_kind IS NULL OR settlement_kind IN (
      'resolved', 'dismissed', 'superseded', 'legacy_archived', 'expired'
    ));
''',
]);
