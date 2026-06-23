import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';

import 'beacon_hud_action_button.dart';

/// Compact HUD header: metadata strip, NOW/YOU, action rail.
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.onAuthorTap,
    this.onUpdateStatus,
    this.onOfferHelp,
    this.onForward,
    this.onWatch,
    this.onStopWatching,
    this.onSwitchToPeopleTab,
    this.onEditNowLine,
    this.onOpenItemDiscussion,
    super.key,
  });

  final BeaconViewState state;

  final VoidCallback onAuthorTap;

  final VoidCallback? onUpdateStatus;
  final VoidCallback? onOfferHelp;
  final VoidCallback? onForward;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;

  /// Switches to the People lens (tab index 1).
  final VoidCallback? onSwitchToPeopleTab;

  /// Edit room current line (NOW row).
  final VoidCallback? onEditNowLine;

  /// Opens an item discussion thread (YOU sheet Reply action).
  final void Function(CoordinationItem item)? onOpenItemDiscussion;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final specs = _buildHudActions(l10n);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        8,
        tt.screenHPadding,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BeaconHudMetadataTable(
            buildEntries: (rowWidth) => buildBeaconViewHudMetadataEntries(
              context,
              rowWidth: rowWidth,
              state: state,
              onFacePileTap: onSwitchToPeopleTab,
              onEditNowLine: onEditNowLine,
            ),
          ),
          if (state.beacon.lifecycle == BeaconLifecycle.reviewOpen)
            ReviewWindowBannerHost(
              beaconId: state.beacon.id,
              isAuthor: state.isBeaconMine,
              onManageStatus: onUpdateStatus,
            )
          else if (specs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _HudActionRail(actions: specs),
            const SizedBox(height: 10),
          ],
          Divider(height: 1, color: tt.border),
        ],
      ),
    );
  }

  List<_HudActionSpec> _buildHudActions(L10n l10n) {
    final b = state.beacon;
    final open = b.lifecycle == BeaconLifecycle.open;

    if (b.lifecycle == BeaconLifecycle.deleted ||
        b.lifecycle == BeaconLifecycle.reviewOpen ||
        !open) {
      return const [];
    }

    if (state.isAuthorOrSteward) {
      final specs = <_HudActionSpec>[];
      if (onForward != null) {
        specs.add(
          _HudActionSpec(
            icon: Icons.send_outlined,
            label: l10n.labelForward,
            onPressed: onForward,
            filled: false,
          ),
        );
      }
      if (onUpdateStatus != null) {
        specs.add(
          _HudActionSpec(
            icon: Icons.tune_outlined,
            label: l10n.beaconCtaUpdateStatus,
            onPressed: onUpdateStatus,
            filled: false,
          ),
        );
      }
      return specs;
    }

    final canOfferHelp = open &&
        !state.isHelpOffered &&
        b.allowsNewHelpOfferAsNonAuthor &&
        onOfferHelp != null;

    if (canOfferHelp) {
      final out = <_HudActionSpec>[
        _HudActionSpec(
          icon: Icons.volunteer_activism_outlined,
          label: l10n.labelOfferHelp,
          onPressed: onOfferHelp,
          filled: true,
        ),
      ];
      if (onForward != null) {
        out.add(
          _HudActionSpec(
            icon: Icons.send_outlined,
            label: l10n.labelForward,
            onPressed: onForward,
            filled: false,
          ),
        );
      }
      if (state.inboxStatus == InboxItemStatus.needsMe && onWatch != null) {
        out.add(
          _HudActionSpec(
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
          _HudActionSpec(
            icon: Icons.visibility_off_outlined,
            label: l10n.beaconHeaderStopWatching,
            onPressed: onStopWatching,
            filled: false,
          ),
        );
      }
      return out.take(3).toList();
    }

    final out = <_HudActionSpec>[];
    if (onForward != null) {
      out.add(
        _HudActionSpec(
          icon: Icons.send_outlined,
          label: l10n.labelForward,
          onPressed: onForward,
          filled: false,
        ),
      );
    }
    if (state.inboxStatus == InboxItemStatus.needsMe && onWatch != null) {
      out.add(
        _HudActionSpec(
          icon: Icons.visibility_outlined,
          label: l10n.beaconHeaderWatch,
          onPressed: onWatch,
          filled: false,
        ),
      );
    } else if (state.inboxStatus == InboxItemStatus.watching &&
        onStopWatching != null) {
      out.add(
        _HudActionSpec(
          icon: Icons.visibility_off_outlined,
          label: l10n.beaconHeaderStopWatching,
          onPressed: onStopWatching,
          filled: false,
        ),
      );
    }
    return out.take(3).toList();
  }
}

class _HudActionSpec {
  const _HudActionSpec({
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

class _HudActionRail extends StatelessWidget {
  const _HudActionRail({required this.actions});

  final List<_HudActionSpec> actions;

  @override
  Widget build(BuildContext context) {
    return Row(
      // Default cross-axis is center. Avoid stretch: header sits in a sliver with
      // unbounded height, and stretch would pass infinite extent to children.
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i != 0) const SizedBox(width: 8),
          Expanded(
            child: _HudActionButton(spec: actions[i]),
          ),
        ],
      ],
    );
  }
}

class _HudActionButton extends StatelessWidget {
  const _HudActionButton({required this.spec});

  final _HudActionSpec spec;

  @override
  Widget build(BuildContext context) {
    return BeaconHudActionButton(
      icon: spec.icon,
      label: spec.label,
      onPressed: spec.onPressed,
      filled: spec.filled,
    );
  }
}

/// Read-only lifecycle pill (legacy beacon detail strip).
class BeaconCardPillReadOnly extends StatelessWidget {
  const BeaconCardPillReadOnly({required this.l10n, super.key});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.beaconCtaReadOnly,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
