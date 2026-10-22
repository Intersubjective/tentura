import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

/// What of the viewer's standing on this Request the Request page knows,
/// as one comparable value: when it changes, the Questions entry re-reads
/// its access (#655). Realtime does not tell the viewer about each of their
/// own changes, and a brand-new Request has no hint at all.
Object beaconLobbyStanding(BeaconViewState state) => (
  state.beacon.id,
  state.beacon.status,
  state.beaconContentLoaded,
  state.isBeaconMine,
  state.isSteward,
  state.isHelpOffered,
  state.myActiveHelpOffer != null,
  state.myDeclinedHelpOffer != null,
  state.hasRoomAdmission,
  state.inboxStatus,
  state.isInsideRequest,
);
