import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// One helper-side action on the Request screen (offer help, watch, ...).
class BeaconHudActionSpec {
  const BeaconHudActionSpec({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool filled;
}

/// Helper-side actions for a non-author viewer, in display order; shared by
/// the HUD header and the showcase action panel.
class BeaconHelperHudActions {
  const BeaconHelperHudActions({
    this.primary = const [],
  });

  final List<BeaconHudActionSpec> primary;

  bool get hasActions => primary.isNotEmpty;
}

/// Offer help / edit offer / watch / stop watching for [state]'s viewer.
BeaconHelperHudActions buildBeaconHelperHudActions({
  required L10n l10n,
  required BeaconViewState state,
  VoidCallback? onOfferHelp,
  VoidCallback? onEditHelpOffer,
  VoidCallback? onWatch,
  VoidCallback? onStopWatching,
}) {
  final b = state.beacon;
  final openFamily = b.status.isOpenFamily;

  if (b.status == BeaconStatus.deleted ||
      b.status == BeaconStatus.closed ||
      b.status == BeaconStatus.cancelled) {
    return const BeaconHelperHudActions();
  }

  if (state.isBeaconMine) {
    return const BeaconHelperHudActions();
  }

  if (state.isSteward || b.status == BeaconStatus.reviewOpen || !openFamily) {
    return const BeaconHelperHudActions();
  }

  if (b.status == BeaconStatus.enoughHelp && !state.isHelpOffered) {
    final primary = <BeaconHudActionSpec>[];
    if (onOfferHelp != null) {
      primary.add(
        BeaconHudActionSpec(
          icon: Icons.volunteer_activism_outlined,
          label: l10n.beaconOfferHelpAsBackup,
          onPressed: onOfferHelp,
          filled: true,
        ),
      );
    }
    return BeaconHelperHudActions(primary: primary);
  }

  final canOfferHelp =
      openFamily &&
      !state.isHelpOffered &&
      b.allowsNewHelpOfferAsNonAuthor &&
      onOfferHelp != null;

  if (canOfferHelp) {
    final out = <BeaconHudActionSpec>[
      BeaconHudActionSpec(
        icon: Icons.volunteer_activism_outlined,
        label: l10n.labelOfferHelp,
        onPressed: onOfferHelp,
        filled: true,
      ),
    ];
    if (state.inboxStatus == InboxItemStatus.needsMe && onWatch != null) {
      out.add(
        BeaconHudActionSpec(
          icon: Icons.visibility_outlined,
          label: l10n.beaconHeaderWatch,
          onPressed: onWatch,
          filled: false,
        ),
      );
    } else if (state.inboxStatus == InboxItemStatus.watching &&
        onStopWatching != null &&
        out.length < 3) {
      out.add(
        BeaconHudActionSpec(
          icon: Icons.visibility_off_outlined,
          label: l10n.beaconHeaderStopWatching,
          onPressed: onStopWatching,
          filled: false,
        ),
      );
    }
    return BeaconHelperHudActions(primary: out.take(3).toList());
  }

  final canEditHelpOffer =
      openFamily &&
      state.isRoomAdmissionBlocked &&
      !state.coordinationDeniesRoomAdmission &&
      onEditHelpOffer != null;

  if (canEditHelpOffer) {
    return BeaconHelperHudActions(
      primary: [
        BeaconHudActionSpec(
          icon: Icons.edit_outlined,
          label: l10n.beaconCtaEditHelpOffer,
          onPressed: onEditHelpOffer,
          filled: true,
        ),
      ],
    );
  }

  final out = <BeaconHudActionSpec>[];
  if (state.inboxStatus == InboxItemStatus.needsMe && onWatch != null) {
    out.add(
      BeaconHudActionSpec(
        icon: Icons.visibility_outlined,
        label: l10n.beaconHeaderWatch,
        onPressed: onWatch,
        filled: false,
      ),
    );
  } else if (state.inboxStatus == InboxItemStatus.watching &&
      onStopWatching != null) {
    out.add(
      BeaconHudActionSpec(
        icon: Icons.visibility_off_outlined,
        label: l10n.beaconHeaderStopWatching,
        onPressed: onStopWatching,
        filled: false,
      ),
    );
  }
  return BeaconHelperHudActions(primary: out.take(3).toList());
}
