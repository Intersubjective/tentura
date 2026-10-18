part of '_migrations.dart';

/// #398: repair rows left by blocks before 606aaf7b9.
///
/// A block used to withdraw the blocked person's offer (`status = 1`,
/// `withdraw_reason = 'blocked'`) and leave their participant row admitted
/// (`room_access = 3`): the author still saw an active helper while the
/// helper's Requests tab (active offers only) stayed empty. A block now
/// revokes room access the way `revokeOfferUserBeaconRoomAccess` does; this
/// applies the same to the legacy rows.
///
/// - Every non-addressee participant (role 6 keeps access) with a
///   block-withdrawn offer loses room access, on any Request status, and their
///   «offer accepted» dismissal is cleared, as the revoke does.
/// - Offers are not touched. Rows already at no access are not re-stamped.
///
/// Data only, idempotent.
final m0253 = Migration('0253', [
  '''
DELETE FROM public.offer_accepted_dismissal d
USING public.beacon_participant bp, public.beacon_help_offer o
WHERE d.beacon_id = bp.beacon_id AND d.user_id = bp.user_id
  AND o.beacon_id = bp.beacon_id AND o.user_id = bp.user_id
  AND o.status = 1 AND o.withdraw_reason = 'blocked'
  AND bp.room_access <> 0
  AND bp.role <> 6
''',
  '''
UPDATE public.beacon_participant bp
SET room_access = 0, updated_at = now()
FROM public.beacon_help_offer o
WHERE o.beacon_id = bp.beacon_id AND o.user_id = bp.user_id
  AND o.status = 1 AND o.withdraw_reason = 'blocked'
  AND bp.room_access <> 0
  AND bp.role <> 6
''',
]);
