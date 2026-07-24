part of '_migrations.dart';

/// FK-safe account erasure and retention for the durable attention topology:
/// cascade account-scoped attention rows on user delete, and delivery jobs on
/// receipt delete. Occurrence rows are shared history and stay RESTRICT.
final m0125 = Migration('0125', [
  r'''ALTER TABLE public.attention_channel_throttle
        DROP CONSTRAINT attention_channel_throttle_account_id_fkey,
        ADD CONSTRAINT attention_channel_throttle_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_channel_delivery
        DROP CONSTRAINT attention_channel_delivery_account_id_fkey,
        ADD CONSTRAINT attention_channel_delivery_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_channel_delivery
        DROP CONSTRAINT attention_channel_delivery_receipt_id_fkey,
        ADD CONSTRAINT attention_channel_delivery_receipt_id_fkey
          FOREIGN KEY (receipt_id) REFERENCES public.notification_outbox(id) ON DELETE CASCADE;''',
  r'''ALTER TABLE public.attention_occurrence_recipient
        DROP CONSTRAINT attention_occurrence_recipient_account_id_fkey,
        ADD CONSTRAINT attention_occurrence_recipient_account_id_fkey
          FOREIGN KEY (account_id) REFERENCES public."user"(id) ON DELETE CASCADE;''',
]);
