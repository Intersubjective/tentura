part of '_migrations.dart';

/// Budding C4 (Arch §5.4): author invites expire in one place.
///
/// When a Request (`kind = 0`) goes terminal — cancelled (1), deleted (2) or
/// closed (6) — from a non-terminal status, in the same transaction:
/// - its pending `beacon_author_invite` rows become expired (4);
/// - the contacts of their delivery edges are resolved without evidence
///   (`contact_resolve_without_evidence`, m0241), so an unanswered invite
///   never turns into `noisy` (I8);
/// - the invitee's `authorInviteReceived` receipts on the Request are cleared
///   the way `AttentionSystemSettlementPort.clearAuthorInviteReceived` clears
///   them (`cleared_at`, `clear_reason = 'sweep'`, `seen_at` kept if earlier).
///
/// Review (5) does not expire invites: it can reopen (5 → 0/7/8). Every
/// terminal entry point (closure, closure finalize, cancel, delete, account
/// erasure) writes `beacon.status`, so the trigger covers all of them.
final m0245 = Migration('0245', [
  r'''
CREATE FUNCTION public.beacon_author_invite_expire_on_terminal() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _i record;
BEGIN
  FOR _i IN
    UPDATE public.beacon_author_invite
    SET status = 4, resolved_at = now(), resolved_by = NULL
    WHERE beacon_id = NEW.id AND status = 0
    RETURNING invitee_id, forward_edge_id
  LOOP
    IF _i.forward_edge_id IS NOT NULL THEN
      PERFORM public.contact_resolve_without_evidence(_i.forward_edge_id);
    END IF;
    UPDATE public.notification_outbox AS outbox
    SET cleared_at = now(),
        clear_reason = 'sweep',
        seen_at = COALESCE(outbox.seen_at, now())
    FROM public.attention_occurrence AS occ
    WHERE outbox.occurrence_id = occ.id
      AND occ.event_type = 'authorInviteReceived'
      AND outbox.beacon_id = NEW.id
      AND outbox.account_id = _i.invitee_id
      AND NOT outbox.requires_action
      AND outbox.cleared_at IS NULL;
  END LOOP;
  RETURN NULL;
END;
$$
''',
  '''
CREATE TRIGGER beacon_author_invite_expire_trg
    AFTER UPDATE OF status ON public.beacon
    FOR EACH ROW
    WHEN (NEW.kind = 0
          AND NEW.status IN (1, 2, 6)
          AND OLD.status NOT IN (1, 2, 6))
    EXECUTE FUNCTION public.beacon_author_invite_expire_on_terminal()
''',
]);
