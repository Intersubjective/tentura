import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/evaluation/ui/widget/review_window_banner_host.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_you_responsibility_line.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import 'beacon_hud_action_button.dart';

/// Compact HUD header: metadata strip, NOW/YOU, action rail.
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.onAuthorTap,
    this.onUpdateStatus,
    this.onPostUpdate,
    this.onOfferHelp,
    this.onForward,
    this.onWatch,
    this.onStopWatching,
    this.onViewChain,
    this.onSwitchToPeopleTab,
    this.onCloseBeacon,
    this.onOpenRoomSurface,
    this.onOpenReview,
    this.onOpenLogTab,
    this.onEditNowLine,
    this.onShowNowDetail,
    this.onOpenItemDiscussion,
    super.key,
  });

  final BeaconViewState state;

  final VoidCallback onAuthorTap;

  final VoidCallback? onUpdateStatus;
  final VoidCallback? onPostUpdate;
  final VoidCallback? onOfferHelp;
  final VoidCallback? onForward;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final VoidCallback? onViewChain;

  /// Switches to the People lens (tab index 1).
  final VoidCallback? onSwitchToPeopleTab;

  /// Author-only: close beacon (confirm + mutation), wired from screen when allowed.
  final VoidCallback? onCloseBeacon;

  /// Opens Room surface (resolve blockers / coordination).
  final VoidCallback? onOpenRoomSurface;

  /// Closed beacon: open contribution review.
  final VoidCallback? onOpenReview;

  /// Closed beacon: switch to Log tab.
  final VoidCallback? onOpenLogTab;

  /// Edit room current line (NOW row).
  final VoidCallback? onEditNowLine;

  /// Opens NOW detail bottom sheet.
  final VoidCallback? onShowNowDetail;

  /// Opens an item discussion thread (YOU sheet Reply action).
  final void Function(CoordinationItem item)? onOpenItemDiscussion;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final nowDisplay = beaconHudNowDisplay(l10n, state);
    final youResponsibility = state.youResponsibility ??
        CoordinationResponsibility(beaconId: state.beacon.id);

    final bundle = _buildHudActions(l10n);
    final activeHelpUsers = [
      for (final offer in state.helpOffers)
        if (!offer.isWithdrawn) offer.user,
    ];
    final viewerId = context.watch<ProfileCubit>().state.profile.id;
    final phaseInput = beaconPhaseInputFromViewState(state);
    final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
    final openBlocker = phaseInput.openBlocker;

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
          BeaconHudMetadataColumn(
            children: [
              BeaconCompactMetadataStrip(
                beacon: state.beacon,
                involvedProfiles: activeHelpUsers,
                currentUserId: viewerId,
                onFacePileTap: onSwitchToPeopleTab,
              ),
              HudLabeledMultiline(
                leadingIcon: BeaconHudRowIcons.now,
                semanticsLabel: l10n.beaconHudNowLabel,
                text: nowDisplay.primaryText,
                subline: nowDisplay.blockerText,
                mutedColor: tt.textMuted,
                isPlaceholder: nowDisplay.isPlaceholder,
                onEdit: onEditNowLine,
                editSemanticLabel: l10n.beaconHudEditNowLine,
                onShowDetail: onShowNowDetail,
                showDetailSemanticLabel: l10n.beaconHudNowLabel,
              ),
              BeaconYouResponsibilityLine(
                beacon: state.beacon,
                responsibility: youResponsibility,
                isAuthorOrSteward: state.isAuthorOrSteward,
                showNewBadges: false,
                viewerUserId: viewerId,
                openBlocker: openBlocker,
                phaseResult: phaseResult,
              ),
            ],
          ),
          if (state.beacon.lifecycle == BeaconLifecycle.reviewOpen)
            ReviewWindowBannerHost(beaconId: state.beacon.id)
          else if (bundle.specs.isNotEmpty || bundle.showOverflowClose) ...[
            const SizedBox(height: 10),
            _HudActionRail(
              actions: bundle.specs,
              trailing: bundle.showOverflowClose && onCloseBeacon != null
                  ? _HudCloseOverflowButton(
                      l10n: l10n,
                      onPressed: onCloseBeacon!,
                    )
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          Divider(height: 1, color: tt.border),
        ],
      ),
    );
  }

  _HudActionBundle _buildHudActions(L10n l10n) {
    final b = state.beacon;
    final open = b.lifecycle == BeaconLifecycle.open;

    if (b.lifecycle == BeaconLifecycle.deleted) {
      return const _HudActionBundle(specs: [], showOverflowClose: false);
    }

    if (b.lifecycle == BeaconLifecycle.reviewOpen) {
      return const _HudActionBundle(specs: [], showOverflowClose: false);
    }

    if (!open) {
      final out = <_HudActionSpec>[];
      if (onOpenReview != null) {
        out.add(
          _HudActionSpec(
            icon: Icons.rate_review_outlined,
            label: l10n.beaconHudCtaReviewContributions,
            onPressed: onOpenReview,
            filled: false,
          ),
        );
      }
      if (onOpenLogTab != null && out.length < 3) {
        out.add(
          _HudActionSpec(
            icon: Icons.format_list_bulleted_outlined,
            label: l10n.beaconHudCtaOpenLog,
            onPressed: onOpenLogTab,
            filled: false,
          ),
        );
      }
      if (onViewChain != null && out.length < 3) {
        out.add(
          _HudActionSpec(
            icon: Icons.account_tree_outlined,
            label: l10n.beaconCtaViewChain,
            onPressed: onViewChain,
            filled: false,
          ),
        );
      }
      return _HudActionBundle(specs: out.take(3).toList(), showOverflowClose: false);
    }

    if (state.isAuthorOrSteward) {
      final cp = state.closureActionPriority;
      final readiness = state.closureReadiness;
      final showResolve = readiness == BeaconClosureReadiness.blocked &&
          onOpenRoomSurface != null &&
          state.canNavigateBeaconRoom;

      final overflowClose =
          cp == ClosureActionPriority.overflow && onCloseBeacon != null;

      final specs = <_HudActionSpec>[];

      void addPostUpdate() {
        if (onPostUpdate == null) return;
        specs.add(
          _HudActionSpec(
            icon: Icons.edit_note_outlined,
            label: l10n.postUpdateCTA,
            onPressed: onPostUpdate,
            filled: false,
          ),
        );
      }

      void addForward() {
        if (onForward == null) return;
        specs.add(
          _HudActionSpec(
            icon: Icons.send_outlined,
            label: l10n.labelForward,
            onPressed: onForward,
            filled: false,
          ),
        );
      }

      void addClose({required bool filled}) {
        if (onCloseBeacon == null) return;
        specs.add(
          _HudActionSpec(
            icon: Icons.flag_outlined,
            label: l10n.buttonClose,
            onPressed: onCloseBeacon,
            filled: filled,
          ),
        );
      }

      void addResolve() {
        if (onOpenRoomSurface == null) return;
        specs.add(
          _HudActionSpec(
            icon: Icons.bolt_outlined,
            label: l10n.beaconHudResolveBlocker,
            onPressed: onOpenRoomSurface,
            filled: false,
          ),
        );
      }

      void addUpdateStatus() {
        if (onUpdateStatus == null) return;
        if (state.unansweredHelpOffersCount != 0) return;
        specs.add(
          _HudActionSpec(
            icon: Icons.tune_outlined,
            label: l10n.beaconCtaUpdateStatus,
            onPressed: onUpdateStatus,
            filled: false,
          ),
        );
      }

      if (showResolve) {
        addPostUpdate();
        addResolve();
        addForward();
      } else {
        switch (cp) {
          case ClosureActionPriority.primary:
            addClose(filled: true);
            addPostUpdate();
            addForward();
          case ClosureActionPriority.secondary:
            addPostUpdate();
            addClose(filled: false);
            addForward();
          case ClosureActionPriority.overflow:
          case ClosureActionPriority.hidden:
            addPostUpdate();
            addForward();
        }
        if (specs.length < 3) {
          addUpdateStatus();
        }
      }

      while (specs.length > 3) {
        var removed = false;
        for (var i = specs.length - 1; i >= 0; i--) {
          final l = specs[i].label;
          if (l == l10n.beaconCtaUpdateStatus) {
            specs.removeAt(i);
            removed = true;
            break;
          }
        }
        if (!removed) {
          for (var i = specs.length - 1; i >= 0; i--) {
            if (specs[i].label == l10n.labelForward) {
              specs.removeAt(i);
              break;
            }
          }
        }
      }

      return _HudActionBundle(
        specs: specs.take(3).toList(growable: false),
        showOverflowClose: overflowClose,
      );
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
      return _HudActionBundle(specs: out.take(3).toList(), showOverflowClose: false);
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
    if (onViewChain != null && out.length < 3) {
      out.add(
        _HudActionSpec(
          icon: Icons.account_tree_outlined,
          label: l10n.beaconCtaViewChain,
          onPressed: onViewChain,
          filled: false,
        ),
      );
    }
    return _HudActionBundle(specs: out.take(3).toList(), showOverflowClose: false);
  }
}

class _HudActionBundle {
  const _HudActionBundle({
    required this.specs,
    required this.showOverflowClose,
  });

  final List<_HudActionSpec> specs;
  final bool showOverflowClose;
}

class _HudCloseOverflowButton extends StatelessWidget {
  const _HudCloseOverflowButton({
    required this.l10n,
    required this.onPressed,
  });

  final L10n l10n;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: l10n.beaconHudOverflowMore,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 40),
      icon: Icon(Icons.more_horiz, color: scheme.onSurface),
      onSelected: (value) {
        if (value == 'close') {
          onPressed();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'close',
          child: Text(l10n.beaconHudOverflowCloseBeacon),
        ),
      ],
    );
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
  const _HudActionRail({
    required this.actions,
    this.trailing,
  });

  final List<_HudActionSpec> actions;
  final Widget? trailing;

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
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
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
