import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import '../bloc/beacon_view_state.dart';

/// Operational header for beacon detail: identity, anchor status, one primary CTA,
/// secondary ghost chips (same visual family).
class BeaconOperationalHeaderCard extends StatelessWidget {
  const BeaconOperationalHeaderCard({
    required this.state,
    required this.overflowMenu,
    required this.onAuthorTap,
    this.onUpdateStatus,
    this.onPostUpdate,
    this.onCommit,
    this.onUpdateCommitment,
    this.onForward,
    this.onWatch,
    this.onStopWatching,
    this.onRoom,
    this.onViewChain,
    super.key,
  });

  final BeaconViewState state;

  /// Overflow menu widget (BeaconOverflowMenu) wired like app bar (⋮).
  final Widget overflowMenu;

  final VoidCallback onAuthorTap;

  final VoidCallback? onUpdateStatus;
  final VoidCallback? onPostUpdate;
  final VoidCallback? onCommit;
  final VoidCallback? onUpdateCommitment;
  final VoidCallback? onForward;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final VoidCallback? onRoom;
  final VoidCallback? onViewChain;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final beacon = state.beacon;
    final open = beacon.lifecycle == BeaconLifecycle.open;

    final activeCommitCount =
        state.commitments.where((c) => !c.isWithdrawn).length;

    final anchorTone = _anchorTone(beacon.coordinationStatus);

    final roomCount = state.roomParticipants.length;

    final canCommit = !state.isBeaconMine &&
        open &&
        !state.isCommitted &&
        beacon.allowsNewCommitAsNonAuthor &&
        onCommit != null;

    final updateCommitment =
        !state.isBeaconMine &&
            open &&
            state.isCommitted &&
            onUpdateCommitment != null;

    var primaryFilledForwardOnly = false;

    Widget primaryBlock = const SizedBox.shrink();
    if (!state.isBeaconMine && open) {
      if (canCommit) {
        primaryBlock = _PrimaryCtaSlot(
          child: FilledButton(
            onPressed: onCommit,
            child: Text(l10n.labelCommit),
          ),
        );
      } else if (updateCommitment) {
        primaryBlock = _PrimaryCtaSlot(
          child: FilledButton(
            onPressed: onUpdateCommitment,
            child: Text(l10n.beaconHeaderUpdateCommitment),
          ),
        );
      } else if (onForward != null) {
        primaryFilledForwardOnly = true;
        primaryBlock = _PrimaryCtaSlot(
          child: FilledButton(
            onPressed: onForward,
            child: Text(l10n.labelForward),
          ),
        );
      }
    }

    final chips = <Widget>[];

    if (open && state.isBeaconMine && onPostUpdate != null) {
      chips.add(
        _HeaderChip(
          icon: Icons.add,
          label: l10n.postUpdateCTA,
          onPressed: onPostUpdate,
        ),
      );
    }

    if (open && onForward != null && !primaryFilledForwardOnly) {
      chips.add(
        _HeaderChip(
          icon: Icons.send_outlined,
          label: l10n.labelForward,
          onPressed: onForward,
        ),
      );
    }

    if (open &&
        state.inboxStatus == InboxItemStatus.needsMe &&
        onWatch != null) {
      chips.add(
        _HeaderChip(
          icon: Icons.visibility_outlined,
          label: l10n.beaconHeaderWatch,
          onPressed: onWatch,
        ),
      );
    } else if (open &&
        state.inboxStatus == InboxItemStatus.watching &&
        onStopWatching != null) {
      chips.add(
        _HeaderChip(
          icon: Icons.visibility_off_outlined,
          label: l10n.beaconHeaderStopWatching,
          onPressed: onStopWatching,
        ),
      );
    }

    if (state.canNavigateBeaconRoom && onRoom != null) {
      chips.add(
        _HeaderChip(
          icon: Icons.forum_outlined,
          label: l10n.beaconHeaderRoomCount(roomCount),
          onPressed: onRoom,
        ),
      );
    } else if (state.isRoomAdmissionBlocked) {
      chips.add(
        _HeaderChip(
          icon: Icons.forum_outlined,
          label: state.coordinationDeniesRoomAdmission
              ? l10n.beaconRoomNoAdmission
              : l10n.beaconRoomWaitingForApproval,
        ),
      );
    }

    final secondaryRow = chips.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: Wrap(
              spacing: tt.rowGap / 2,
              runSpacing: tt.rowGap / 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          );

    Widget readOnlyExtras = const SizedBox.shrink();
    if (!open) {
      readOnlyExtras = Padding(
        padding: EdgeInsets.only(top: tt.rowGap / 2),
        child: Row(
          children: [
            BeaconCardPillReadOnly(l10n: l10n),
            const Spacer(),
            if (onViewChain != null)
              IconButton(
                onPressed: onViewChain,
                icon: const Icon(TenturaIcons.graph, size: 22),
                style: IconButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                tooltip: l10n.beaconCtaViewChain,
              ),
          ],
        ),
      );
    }

    final outerPadding = EdgeInsets.fromLTRB(
      tt.screenHPadding,
      tt.rowGap / 2,
      tt.screenHPadding,
      tt.rowGap / 2,
    );

    final showPrimaryGap =
        open &&
            !state.isBeaconMine &&
            (canCommit || updateCommitment || primaryFilledForwardOnly);

    return Padding(
      padding: outerPadding,
      child: TenturaTechCard(
        padding: tt.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            BeaconCardHeaderRow(
              beacon: beacon,
              menu: overflowMenu,
              titleStyle: TenturaText.title(scheme.onSurface),
            ),
            SizedBox(height: tt.rowGap / 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAuthorTap,
              child: _MetaAuthorCategoryDueRow(beacon: beacon),
            ),
            if (beacon.hasNeedSummary) ...[
              SizedBox(height: tt.rowGap / 2),
              Text(
                '${l10n.beaconNeedBriefPrefix} ${beacon.needSummary!.trim()}',
                style: TenturaText.body(tt.textMuted),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: tt.rowGap / 2),
            if (open && state.isBeaconMine && onUpdateStatus != null)
              InkWell(
                onTap: onUpdateStatus,
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: _anchorToneColor(anchorTone, tt),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TenturaStatusText(
                        _anchorLine(l10n, beacon, activeCommitCount),
                        tone: anchorTone,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              )
            else
              TenturaStatusText(
                _anchorLine(l10n, beacon, activeCommitCount),
                tone: anchorTone,
                maxLines: 2,
              ),
            if (showPrimaryGap) ...[
              SizedBox(height: tt.sectionGap / 2),
              primaryBlock,
            ],
            secondaryRow,
            readOnlyExtras,
          ],
        ),
      ),
    );
  }

  static Color _anchorToneColor(TenturaTone tone, TenturaTokens tt) =>
      switch (tone) {
        TenturaTone.neutral => tt.textMuted,
        TenturaTone.info => tt.info,
        TenturaTone.good => tt.good,
        TenturaTone.warn => tt.warn,
        TenturaTone.danger => tt.danger,
      };

  static TenturaTone _anchorTone(BeaconCoordinationStatus s) =>
      switch (s) {
        BeaconCoordinationStatus.noCommitmentsYet => TenturaTone.neutral,
        BeaconCoordinationStatus.commitmentsWaitingForReview =>
          TenturaTone.info,
        BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
          TenturaTone.warn,
        BeaconCoordinationStatus.enoughHelpCommitted => TenturaTone.good,
      };

  static String _anchorLine(L10n l10n, Beacon beacon, int activeCommitCount) {
    final coord = coordinationStatusLabel(l10n, beacon.coordinationStatus);
    final committedPart = activeCommitCount == 0
        ? l10n.beaconHeaderNoCommitments
        : l10n.beaconHeaderCommitmentsCount(activeCommitCount);
    return '$coord · $committedPart';
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

class _PrimaryCtaSlot extends StatelessWidget {
  const _PrimaryCtaSlot({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth * 0.65;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: w.clamp(120.0, constraints.maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = onPressed == null;
    final fg =
        muted ? scheme.onSurfaceVariant.withValues(alpha: 0.54) : scheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: fg),
      label: Text(
        label,
        style: TenturaText.command(fg),
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        foregroundColor: fg,
        disabledForegroundColor: fg,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _MetaAuthorCategoryDueRow extends StatelessWidget {
  const _MetaAuthorCategoryDueRow({required this.beacon});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sepStyle = beaconCardMetadataStripTextStyle(theme);

    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, profileState) {
        final author = beacon.author;
        final name = SelfUserHighlight.displayName(
          l10n,
          author,
          profileState.profile.id,
        );
        final nameStyle = SelfUserHighlight.nameStyle(
          theme,
          theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          SelfUserHighlight.profileIsSelf(author, profileState.profile.id),
        );

        final category = beaconCardCategoryLabel(beacon, l10n);

        final parts = <InlineSpan>[
          TextSpan(text: name, style: nameStyle),
          TextSpan(text: ' · ', style: sepStyle),
          TextSpan(
            text: category,
            style: beaconCardMetadataStripTextStyle(theme),
          ),
        ];

        final end = beacon.endAt;
        if (end != null) {
          parts.addAll([
            TextSpan(text: ' · ', style: sepStyle),
            TextSpan(
              text: l10n.beaconChipDeadlineOn(dateFormatYMD(end)),
              style: beaconCardMetadataStripTextStyle(theme),
            ),
          ]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelfAwareAvatar(
              profile: author,
              size: 22,
              withRating: false,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: RichText(
                text: TextSpan(children: parts),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
