import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// U088 — who sees the way into the lobby: the author of a Request, and a
/// viewer with a live help offer on it. (The server checks again, and also
/// keeps out people the author removed.)
bool canOpenBeaconLobby(BeaconViewState state) =>
    state.beacon.isRequest &&
    (state.isBeaconMine || state.myActiveHelpOffer != null);

/// Row on the request's Overview that opens the lobby.
class BeaconLobbyEntryRow extends StatelessWidget {
  const BeaconLobbyEntryRow({required this.state, super.key});

  final BeaconViewState state;

  @override
  Widget build(BuildContext context) {
    if (!canOpenBeaconLobby(state)) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    return ListTile(
      key: const Key('beaconLobbyEntry'),
      leading: const Icon(Icons.forum_outlined),
      title: Text(l10n.beaconLobbyTitle),
      subtitle: Text(l10n.beaconLobbyEntrySubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.router.push(
        BeaconLobbyRoute(
          beaconId: state.beacon.id,
          knownNames: {
            for (final o in state.helpOffers) o.user.id: o.user.shownName,
          },
        ),
      ),
    );
  }
}
