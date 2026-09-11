import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';

/// Shared C2 classification for an authorized pinned Request (Beacon).
enum ConstellationPinnedBeaconLayer {
  /// Readable anchor only; not filter-hidden (permanent non-renderable states).
  dormantAnchor,

  /// Authorized and renderable under lifecycle rules, but excluded by filters.
  filterHidden,

  /// Eligible for [ConstellationAnchorProjection.pinnedRequests] and support.
  visiblePinned,
}

ConstellationPinnedBeaconLayer classifyAuthorizedPinnedBeacon({
  required int status,
  required bool showClosed,
  required bool participatedOnly,
  required bool viewerParticipates,
}) {
  if (!isKnownConstellationBeaconStatus(status)) {
    return ConstellationPinnedBeaconLayer.dormantAnchor;
  }
  final lifecycleOk = constellationBeaconStatusPermittedInField(
    status: status,
    showClosed: showClosed,
  );
  if (!lifecycleOk) {
    if (constellationBeaconStatusPermittedInField(
      status: status,
      showClosed: true,
    )) {
      return ConstellationPinnedBeaconLayer.filterHidden;
    }
    return ConstellationPinnedBeaconLayer.dormantAnchor;
  }
  if (participatedOnly && !viewerParticipates) {
    return ConstellationPinnedBeaconLayer.filterHidden;
  }
  return ConstellationPinnedBeaconLayer.visiblePinned;
}

/// SQL fragment: true when [viewerId] participates on beacon alias [beaconAlias].
/// [beaconAlias] must be a bare table alias (e.g. `b`).
String constellationViewerParticipatesSql({
  required String viewerParam,
  required String beaconAlias,
}) {
  return '''
(
  $beaconAlias.user_id = $viewerParam
  OR EXISTS (
    SELECT 1 FROM public.beacon_commitment_event e
    WHERE e.beacon_id = $beaconAlias.id
      AND e.user_id = $viewerParam
      AND e.kind = 1
  )
  OR EXISTS (
    SELECT 1 FROM public.beacon_help_offer_admission_event ae
    WHERE ae.beacon_id = $beaconAlias.id
      AND ae.offer_user_id = $viewerParam
      AND ae.action IN (0, 1)
  )
  OR EXISTS (
    SELECT 1 FROM public.beacon_participant bp
    WHERE bp.beacon_id = $beaconAlias.id
      AND bp.user_id = $viewerParam
      AND (bp.role = 1 OR bp.room_access = 3)
  )
  OR EXISTS (
    SELECT 1 FROM public.beacon_help_offer ho
    WHERE ho.beacon_id = $beaconAlias.id
      AND ho.user_id = $viewerParam
      AND ho.status = 0
      AND NOT EXISTS (
        SELECT 1 FROM public.beacon_help_offer_admission_event ae2
        WHERE ae2.beacon_id = ho.beacon_id
          AND ae2.offer_user_id = ho.user_id
          AND ae2.action IN (2, 3)
          AND ae2.seq = (
            SELECT MAX(ae3.seq)
            FROM public.beacon_help_offer_admission_event ae3
            WHERE ae3.beacon_id = ho.beacon_id
              AND ae3.offer_user_id = ho.user_id
          )
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.beacon_help_offer_coordination c
        WHERE c.offer_beacon_id = ho.beacon_id
          AND c.offer_user_id = ho.user_id
          AND c.response_type = 4
      )
  )
)
''';
}
