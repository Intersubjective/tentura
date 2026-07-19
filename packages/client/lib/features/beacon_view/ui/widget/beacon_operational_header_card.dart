import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';

import 'beacon_definition_hud_row.dart';
import 'beacon_hud_action_button.dart';
import 'beacon_hud_author_act_block.dart';
import 'closed_request_banner.dart';

/// Compact HUD header: metadata strip, NOW/YOU, action rail.
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.onAuthorTap,
    this.onAuthorHudAction,
    this.onOfferHelp,
    this.onEditHelpOffer,
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

  final void Function(BeaconHudAuthorAction action)? onAuthorHudAction;
  final VoidCallback? onOfferHelp;
  final VoidCallback? onEditHelpOffer;
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
    final authorSpec = state.isBeaconMine && onAuthorHudAction != null
        ? deriveBeaconHudAuthorActSpec(l10n: l10n, state: state)
        : null;
    final specs = authorSpec == null
        ? _buildHelperHudActions(l10n)
        : const <_HudActionSpec>[];

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
          ClosedRequestBanner(beacon: state.beacon),
          BeaconHudMetadataTable(
            buildEntries: (rowWidth) => buildBeaconViewHudMetadataEntries(
              context,
              rowWidth: rowWidth,
              state: state,
              onFacePileTap: onSwitchToPeopleTab,
              onEditNowLine: onEditNowLine,
            ),
          ),
          const SizedBox(height: kBeaconHudRowGap),
          BeaconDefinitionHudRow(beacon: state.beacon),
          if (state.beacon.status == BeaconStatus.reviewOpen)
            ReviewWindowBannerHost(
              reviewWindowInfo: state.reviewWindowInfo,
              isAuthor: state.isBeaconMine,
            ),
          if (authorSpec != null) ...[
            const SizedBox(height: 10),
            BeaconHudAuthorActBlock(
              spec: authorSpec,
              onPressed: state.isLoading
                  ? null
                  : () => onAuthorHudAction!(authorSpec.action),
            ),
            const SizedBox(height: 10),
          ] else if (specs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _HudActionRail(actions: specs),
            const SizedBox(height: 10),
          ],
          Divider(height: 1, color: tt.border),
        ],
      ),
    );
  }

  List<_HudActionSpec> _buildHelperHudActions(L10n l10n) {
    final b = state.beacon;
    final openFamily = b.status.isOpenFamily;

    if (b.status == BeaconStatus.deleted ||
        b.status == BeaconStatus.closed ||
        b.status == BeaconStatus.cancelled) {
      return const [];
    }

    if (state.isBeaconMine) {
      return const [];
    }

    if (state.isSteward || b.status == BeaconStatus.reviewOpen || !openFamily) {
      return const [];
    }

    final canOfferHelp = openFamily &&
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

    final canEditHelpOffer = openFamily &&
        state.isRoomAdmissionBlocked &&
        !state.coordinationDeniesRoomAdmission &&
        onEditHelpOffer != null;

    if (canEditHelpOffer) {
      final out = <_HudActionSpec>[
        _HudActionSpec(
          icon: Icons.edit_outlined,
          label: l10n.beaconCtaEditHelpOffer,
          onPressed: onEditHelpOffer,
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
    final wide = context.windowClass != WindowClass.compact;
    return Row(
      // Default cross-axis is center. Avoid stretch: header sits in a sliver with
      // unbounded height, and stretch would pass infinite extent to children.
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i != 0) const SizedBox(width: 8),
          if (wide)
            _HudActionButton(spec: actions[i])
          else
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
