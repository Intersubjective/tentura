part of '_migrations.dart';

/// Budding B5 (Arch §2.5, §5.4, I8): `contact_resolve_without_evidence`
/// resolves an unresolved contact edge the way a sender cancel does
/// (`contact_edge_on_cancel`: resolved, outcome NULL) and writes no evidence.
/// Invite expiry and withdrawal use it so a warm or expired invite never turns
/// into `noisy`. Returns whether the edge was resolved by this call.
///
/// The sweep side (`claimIgnoredContacts` skips `contact_sweep_exempt` edges)
/// is in `ForwardEdgeRepository`.
final m0241 = Migration('0241', [
  r'''
CREATE FUNCTION public.contact_resolve_without_evidence(p_edge text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  _n integer;
BEGIN
  UPDATE public.beacon_forward_edge
  SET contact_resolved_at = now()
  WHERE id = p_edge
    AND contact_deadline_at IS NOT NULL
    AND contact_resolved_at IS NULL;
  GET DIAGNOSTICS _n = ROW_COUNT;
  RETURN _n = 1;
END;
$$
''',
]);
