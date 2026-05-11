import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_anchor_status.dart';

/// Compact HUD header: state tokens, NOW/YOU, people strip, action rail.
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.onAuthorTap,
    this.onUpdateStatus,
    this.onPostUpdate,
    this.onCommit,
    this.onForward,
    this.onWatch,
    this.onStopWatching,
    this.onViewChain,
    this.onSwitchToPeopleTab,
    this.onCloseBeacon,
    this.onOpenRoomSurface,
    this.onOpenReview,
    this.onOpenLogTab,
    super.key,
  });

  final BeaconViewState state;

  final VoidCallback onAuthorTap;

  final VoidCallback? onUpdateStatus;
  final VoidCallback? onPostUpdate;
  final VoidCallback? onCommit;
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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final beacon = state.beacon;

    final activeCommitCount =
        state.commitments.where((c) => !c.isWithdrawn).length;
    final needCoordinationCount = state.commitments
        .where(
          (c) =>
              !c.isWithdrawn &&
              c.coordinationResponse ==
                  CoordinationResponseType.needCoordination,
        )
        .length;

    final authorClosure = state.isBeaconMine &&
            beacon.lifecycle == BeaconLifecycle.open
        ? state.closureReadiness
        : null;

    final tokens = buildBeaconHudStateTokens(
      l10n: l10n,
      beacon: beacon,
      activeCommitCount: activeCommitCount,
      needCoordinationCount: needCoordinationCount,
      cue: state.beaconRoomCue,
      authorClosureReadiness: authorClosure,
    );
    final visibleTokens = tokens.length > 3 ? tokens.sublist(0, 3) : tokens;

    final nowText = beaconHudNowLine(l10n, state);
    final youText = beaconHudYouLine(l10n, state);

    final bundle = _buildHudActions(l10n);

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
          _HudStateTokenRow(tokens: visibleTokens),
          const SizedBox(height: 8),
          _HudLabeledMultiline(
            label: l10n.beaconHudNowLabel,
            text: nowText,
            mutedColor: tt.textMuted,
          ),
          const SizedBox(height: 6),
          _HudLabeledMultiline(
            label: l10n.beaconHudYouLabel,
            text: youText,
            mutedColor: tt.textMuted,
          ),
          const SizedBox(height: 8),
          _HudPeopleStrip(
            state: state,
            onTap: onSwitchToPeopleTab,
          ),
          if (bundle.specs.isNotEmpty || bundle.showOverflowClose) ...[
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

    if (state.isBeaconMine) {
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
        if (state.unansweredCommitmentsCount != 0) return;
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

    final canCommit = open &&
        !state.isCommitted &&
        b.allowsNewCommitAsNonAuthor &&
        onCommit != null;

    if (canCommit) {
      final out = <_HudActionSpec>[
        _HudActionSpec(
          icon: Icons.volunteer_activism_outlined,
          label: l10n.labelCommit,
          onPressed: onCommit,
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
      child: SizedBox(
        width: 44,
        height: 40,
        child: Icon(Icons.more_horiz, color: scheme.onSurface),
      ),
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

class _HudStateTokenRow extends StatelessWidget {
  const _HudStateTokenRow({required this.tokens});

  final List<String> tokens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tokens.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in tokens)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              t,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
      ],
    );
  }
}

class _HudLabeledMultiline extends StatelessWidget {
  const _HudLabeledMultiline({
    required this.label,
    required this.text,
    required this.mutedColor,
  });

  final String label;
  final String text;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: '$label $text',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 44,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: mutedColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HudPeopleStrip extends StatelessWidget {
  const _HudPeopleStrip({
    required this.state,
    this.onTap,
  });

  final BeaconViewState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final beacon = state.beacon;
    final author = beacon.author;
    final active = state.commitments.where((c) => !c.isWithdrawn).toList();

    const maxSlots = 5;
    final ordered = <Profile>[author];
    for (final c in active) {
      if (c.user.id == author.id) continue;
      ordered.add(c.user);
    }
    final slots = ordered.take(maxSlots).toList(growable: false);
    final plus = ordered.length > maxSlots ? ordered.length - maxSlots : 0;

    final child = Row(
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          if (i != 0) const SizedBox(width: 4),
          _HudPersonToken(
            profile: slots[i],
            isAuthor: slots[i].id == author.id,
            semanticLabel: slots[i].id == author.id
                ? l10n.beaconPeopleLensAuthorHeading
                : slots[i].title,
          ),
        ],
        if (plus > 0) ...[
          const SizedBox(width: 6),
          Text(
            '+$plus',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ],
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}

class _HudPersonToken extends StatelessWidget {
  const _HudPersonToken({
    required this.profile,
    required this.isAuthor,
    required this.semanticLabel,
  });

  final Profile profile;
  final bool isAuthor;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            TenturaAvatar(profile: profile, size: 28),
            if (isAuthor)
              Positioned(
                right: -2,
                bottom: -2,
                child: Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
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
    final on = spec.onPressed;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    if (spec.filled) {
      return FilledButton.icon(
        onPressed: on,
        icon: Icon(spec.icon, size: 16),
        label: Text(
          spec.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: on,
      icon: Icon(spec.icon, size: 16),
      label: Text(
        spec.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        visualDensity: VisualDensity.compact,
      ),
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
