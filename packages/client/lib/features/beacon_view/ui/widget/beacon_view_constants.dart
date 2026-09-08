/// Logical surface ids for the request detail screen. Stable across window
/// classes — the visible tab set is a subset, never a re-index.
enum BeaconSurface { now, room, people }

/// ROOM is hidden only when the expanded split is actually active, because the
/// conversation is then permanently visible in the right pane (plan D1/§4.1).
List<BeaconSurface> beaconVisibleSurfaces({required bool isSplit}) =>
    isSplit
        ? const [BeaconSurface.now, BeaconSurface.people]
        : const [BeaconSurface.now, BeaconSurface.room, BeaconSurface.people];
