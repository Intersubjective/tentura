import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/entity/inbox_provenance.dart';
import '../../domain/enum.dart';

String _lifecycleLabel(L10n l10n, BeaconLifecycle lc) => switch (lc) {
  BeaconLifecycle.open => l10n.beaconLifecycleOpen,
  BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
  BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
  BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
  BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
  BeaconLifecycle.closedReviewOpen => l10n.beaconLifecycleClosedReviewOpen,
  BeaconLifecycle.closedReviewComplete =>
    l10n.beaconLifecycleClosedReviewComplete,
};

/// Hours-based remaining time for the inbox metadata wrap (third chip).
({String text, bool urgent})? _hoursRemainingMeta(L10n l10n, DateTime? endAt) {
  if (endAt == null) return null;
  final now = DateTime.now();
  if (!endAt.isAfter(now)) {
    return (text: l10n.inboxDeadlineEnded, urgent: true);
  }
  final d = endAt.difference(now);
  final h = d.inHours;
  if (h < 1) {
    return (text: l10n.inboxDeadlineLessThanHour, urgent: true);
  }
  final urgent = h < 24;
  return (text: l10n.inboxDeadlineHoursRemaining(h), urgent: urgent);
}

/// Beacon **context** for inbox metadata (first column); not tags.
String _beaconContextCategoryLabel(InboxItem item, L10n l10n) {
  final beacon = item.beacon;
  if (beacon == null) return l10n.inboxCategoryGeneral;
  final c = beacon.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

/// Note preview for the primary (MR-ranked) forwarder; used when provenance is collapsed.
String _collapsedProvenancePreviewText(InboxItem item) {
  final p = item.provenance;
  if (p.senders.isNotEmpty) {
    final n = p.senders.first.notePreview;
    if (n.isNotEmpty) {
      return n;
    }
  }
  if (p.strongestNotePreview.isNotEmpty) {
    return p.strongestNotePreview;
  }
  return item.latestNotePreview;
}

/// Matches mock `w-5 h-5` (20px) for collapsed provenance avatars.
const _kProvenanceCollapsedAvatarSize = 20.0;

/// Negative overlap between stacked forwarder avatars (`-space-x-1.5` in mock).
const _kProvenanceAvatarOverlap = 6.0;

/// More than one distinct forwarder (extra rows or overflow text) — only then
/// may the user expand/collapse the provenance block.
bool _provenanceCanExpand(InboxProvenance p) {
  if (p.senders.isEmpty) return false;
  final overflow = p.totalDistinctSenders - p.senders.length;
  return p.senders.length > 1 || overflow > 0;
}

class InboxItemTile extends StatefulWidget {
  const InboxItemTile({
    required this.item,
    required this.onOpenBeacon,
    required this.onTap,
    this.onWatch,
    this.onStopWatching,
    this.onCantHelp,
    this.onMoveToInbox,
    super.key,
  });

  final InboxItem item;
  final VoidCallback onOpenBeacon;
  final VoidCallback onTap;
  final VoidCallback? onWatch;
  final VoidCallback? onStopWatching;
  final Future<void> Function()? onCantHelp;
  final VoidCallback? onMoveToInbox;

  @override
  State<InboxItemTile> createState() => _InboxItemTileState();
}

class _InboxItemTileState extends State<InboxItemTile> {
  var _provenanceExpanded = false;

  @override
  void didUpdateWidget(covariant InboxItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_provenanceCanExpand(widget.item.provenance) && _provenanceExpanded) {
      _provenanceExpanded = false;
    }
  }

  Profile _senderProfile(InboxForwardSender s) => Profile(
    id: s.id,
    title: s.title,
    image: s.imageId != null && s.imageId!.isNotEmpty && s.imageId != 'null'
        ? ImageEntity(id: s.imageId!, authorId: s.id)
        : null,
  );

  String? _secondaryLabel(L10n l10n) {
    if (widget.onCantHelp != null) return l10n.inboxActionNotForMe;
    if (widget.onStopWatching != null) return l10n.actionStopWatching;
    if (widget.onMoveToInbox != null) return l10n.actionMoveToInbox;
    return null;
  }

  Future<void> _onSecondaryPressed() async {
    if (widget.onCantHelp != null) {
      await widget.onCantHelp?.call();
      return;
    }
    if (widget.onStopWatching != null) {
      widget.onStopWatching?.call();
      return;
    }
    widget.onMoveToInbox?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final beacon = widget.item.beacon;
    if (beacon == null) return const SizedBox.shrink();

    final contextCategoryLabel = _beaconContextCategoryLabel(
      widget.item,
      l10n,
    );
    final hoursRemaining = _hoursRemainingMeta(l10n, beacon.endAt);
    final secondaryLabel = _secondaryLabel(l10n);

    final overflow =
        widget.item.provenance.totalDistinctSenders -
        widget.item.provenance.senders.length;
    final showOverflow = overflow > 0;
    final hasProvenanceBody = widget.item.provenance.senders.isNotEmpty;
    final canExpandProvenance = _provenanceCanExpand(widget.item.provenance);

    final lifecycleBg = scheme.primaryFixed;
    // onPrimaryFixed pairs with primaryFixed for readable contrast; the
    // variant role can read as black on some dark-theme seed schemes.
    final lifecycleFg = scheme.onPrimaryFixed;

    final statusPills = <Widget>[
      if (beacon.lifecycle != BeaconLifecycle.open)
        BeaconCardPill(
          label: _lifecycleLabel(l10n, beacon.lifecycle),
          backgroundColor: lifecycleBg,
          foregroundColor: lifecycleFg,
        ),
      if (beacon.coordinationStatus !=
          BeaconCoordinationStatus.noCommitmentsYet)
        BeaconCardPill(
          label: coordinationStatusLabel(l10n, beacon.coordinationStatus),
          backgroundColor: scheme.surfaceContainerHigh,
          foregroundColor: scheme.onSurfaceVariant,
        ),
    ];

    return BeaconCardShell(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: widget.onOpenBeacon,
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BeaconCardHeaderRow(
                        beacon: beacon,
                        titleMaxLines: 2,
                        subline: Row(
                          children: [
                            AvatarRated(
                              profile: beacon.author,
                              size: 22,
                              withRating: false,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                beacon.author.title,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        menu: const SizedBox.shrink(),
                      ),
                      if (statusPills.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Wrap(
                          spacing: kSpacingSmall,
                          runSpacing: kSpacingSmall,
                          children: statusPills,
                        ),
                      ],
                      if (beacon.description.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          beacon.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: kSpacingSmall),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: scheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                      const SizedBox(height: kSpacingSmall),
                      Wrap(
                        spacing: kSpacingMedium,
                        runSpacing: kSpacingSmall,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          BeaconCardMetaItem(
                            icon: Icons.topic_outlined,
                            child: Text(
                              contextCategoryLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          BeaconCardMetaItem(
                            icon: Icons.groups_outlined,
                            child: Text(
                              l10n.inboxCommitmentsCount(
                                beacon.commitmentCount,
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hoursRemaining != null)
                            BeaconCardMetaItem(
                              icon: Icons.timer_outlined,
                              child: Text(
                                hoursRemaining.text,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: hoursRemaining.urgent
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
                                  fontWeight: hoursRemaining.urgent
                                      ? FontWeight.w600
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (beacon.images.isNotEmpty)
                            BeaconCardMetaItem(
                              icon: Icons.photo_library_outlined,
                              child: Text(
                                beacon.images.length > 99
                                    ? '99+'
                                    : '${beacon.images.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      if (widget.item.status == InboxItemStatus.watching ||
                          widget.item.isForwardedByMe) ...[
                        const SizedBox(height: kSpacingSmall),
                        Wrap(
                          spacing: kSpacingSmall,
                          runSpacing: kSpacingSmall,
                          children: [
                            if (widget.item.status == InboxItemStatus.watching)
                              Chip(
                                label: Text(l10n.inboxTabWatching),
                                avatar: Icon(
                                  Icons.visibility_outlined,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                                backgroundColor: scheme.surfaceContainerHighest,
                                side: BorderSide(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                                labelStyle: theme.textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                visualDensity: VisualDensity.compact,
                              ),
                            if (widget.item.isForwardedByMe)
                              Chip(
                                label: Text(l10n.inboxForwardedByMe),
                                avatar: Icon(
                                  Icons.shortcut,
                                  size: 16,
                                  color: scheme.onSurfaceVariant,
                                ),
                                backgroundColor: scheme.surfaceContainerHighest,
                                side: BorderSide(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                                labelStyle: theme.textTheme.labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      ],
                      if (widget.item.status == InboxItemStatus.rejected &&
                          widget.item.rejectionMessage.isNotEmpty) ...[
                        const SizedBox(height: kSpacingSmall),
                        Text(
                          widget.item.rejectionMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (widget.onWatch != null ||
                  widget.onStopWatching != null ||
                  widget.onCantHelp != null ||
                  widget.onMoveToInbox != null)
                PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    if (widget.onWatch != null)
                      PopupMenuItem(
                        value: 'watch',
                        child: Text(l10n.actionWatch),
                      ),
                    if (widget.onStopWatching != null)
                      PopupMenuItem(
                        value: 'stop_watch',
                        child: Text(l10n.actionStopWatching),
                      ),
                    if (widget.onCantHelp != null)
                      PopupMenuItem(
                        value: 'cant_help',
                        child: Text(l10n.actionCantHelp),
                      ),
                    if (widget.onMoveToInbox != null)
                      PopupMenuItem(
                        value: 'move_inbox',
                        child: Text(l10n.actionMoveToInbox),
                      ),
                  ],
                  onSelected: (v) async {
                    if (v == 'watch') widget.onWatch?.call();
                    if (v == 'stop_watch') widget.onStopWatching?.call();
                    if (v == 'cant_help') await widget.onCantHelp?.call();
                    if (v == 'move_inbox') widget.onMoveToInbox?.call();
                  },
                  child: Icon(
                    Icons.more_horiz,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (hasProvenanceBody) ...[
            const SizedBox(height: kSpacingSmall),
            GestureDetector(
              onTap: canExpandProvenance
                  ? () => setState(
                      () => _provenanceExpanded = !_provenanceExpanded,
                    )
                  : null,
              behavior: HitTestBehavior.translucent,
              child: Semantics(
                expanded: canExpandProvenance && _provenanceExpanded,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: kPaddingAllS,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!canExpandProvenance) ...[
                          _ProvenanceCollapsedHeader(
                            primaryProfile: _senderProfile(
                              widget.item.provenance.senders.first,
                            ),
                            primaryName:
                                widget.item.provenance.senders.first.title,
                            restProfiles: [
                              for (
                                var i = 1;
                                i < widget.item.provenance.senders.length;
                                i++
                              )
                                _senderProfile(
                                  widget.item.provenance.senders[i],
                                ),
                            ],
                            overflowCount: showOverflow ? overflow : 0,
                            showExpandAction: false,
                            onExpand: () {},
                          ),
                          const SizedBox(height: kSpacingSmall),
                          _ProvenanceCollapsedQuote(
                            text: _collapsedProvenancePreviewText(
                              widget.item,
                            ),
                            borderColor: scheme.primaryFixedDim,
                          ),
                        ] else ...[
                          if (!_provenanceExpanded)
                            _ProvenanceCollapsedHeader(
                              primaryProfile: _senderProfile(
                                widget.item.provenance.senders.first,
                              ),
                              primaryName:
                                  widget.item.provenance.senders.first.title,
                              restProfiles: [
                                for (
                                  var i = 1;
                                  i < widget.item.provenance.senders.length;
                                  i++
                                )
                                  _senderProfile(
                                    widget.item.provenance.senders[i],
                                  ),
                              ],
                              overflowCount: showOverflow ? overflow : 0,
                              showExpandAction: true,
                              onExpand: () => setState(
                                () => _provenanceExpanded = true,
                              ),
                            ),
                          if (_provenanceExpanded)
                            Semantics(
                              label: l10n.inboxProvenanceTrail,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (
                                    var i = 0;
                                    i < widget.item.provenance.senders.length;
                                    i++
                                  ) ...[
                                    if (i > 0)
                                      const SizedBox(
                                        height: kSpacingMedium,
                                      ),
                                    _ProvenanceSenderBlock(
                                      profile: _senderProfile(
                                        widget.item.provenance.senders[i],
                                      ),
                                      notePreview: widget
                                          .item
                                          .provenance
                                          .senders[i]
                                          .notePreview,
                                      borderColor: i == 0
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                      titleRowTrailing: i == 0
                                          ? TextButton(
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                foregroundColor: scheme.primary,
                                              ),
                                              onPressed: () => setState(
                                                () =>
                                                    _provenanceExpanded = false,
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    l10n.inboxProvenanceCollapse,
                                                    style: theme
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  const Icon(
                                                    Icons.keyboard_arrow_up,
                                                    size: 18,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : null,
                                      noteTopSpacing: i == 0
                                          ? kSpacingSmall
                                          : 6,
                                    ),
                                  ],
                                  if (showOverflow) ...[
                                    const SizedBox(height: kSpacingSmall),
                                    Text(
                                      l10n.inboxMoreForwarders(overflow),
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (!_provenanceExpanded) ...[
                            const SizedBox(height: kSpacingSmall),
                            _ProvenanceCollapsedQuote(
                              text: _collapsedProvenancePreviewText(
                                widget.item,
                              ),
                              borderColor: scheme.primaryFixedDim,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: kSpacingSmall),
          Row(
            children: [
              if (secondaryLabel != null) ...[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _onSecondaryPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.surfaceContainerHigh,
                      foregroundColor: scheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.onCantHelp != null
                              ? Icons.close
                              : widget.onStopWatching != null
                              ? Icons.visibility_off_outlined
                              : Icons.inbox_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            secondaryLabel,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: kSpacingSmall),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: widget.onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_forward,
                        size: 18,
                        color: scheme.onPrimary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.inboxCardOpenBeacon,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Collapsed provenance header: primary avatar + "Name:" | stacked rest avatars + "More".
class _ProvenanceCollapsedHeader extends StatelessWidget {
  const _ProvenanceCollapsedHeader({
    required this.primaryProfile,
    required this.primaryName,
    required this.restProfiles,
    required this.overflowCount,
    required this.showExpandAction,
    required this.onExpand,
  });

  final Profile primaryProfile;
  final String primaryName;
  final List<Profile> restProfiles;
  final int overflowCount;
  final bool showExpandAction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;

    final hasRest = restProfiles.isNotEmpty || overflowCount > 0;

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surfaceContainerLowest),
                ),
                child: AvatarRated(
                  profile: primaryProfile,
                  withRating: false,
                  size: _kProvenanceCollapsedAvatarSize,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${primaryName.trim()}:',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasRest) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '|',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                _ProvenanceOverlappingRestAvatars(
                  profiles: restProfiles,
                  overflowCount: overflowCount,
                  size: _kProvenanceCollapsedAvatarSize,
                  overlap: _kProvenanceAvatarOverlap,
                  ringColor: scheme.surfaceContainerLowest,
                  badgeFillColor: scheme.outlineVariant,
                  badgeTextColor: scheme.surface,
                ),
              ],
            ],
          ),
        ),
        if (showExpandAction)
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: scheme.primary,
            ),
            onPressed: onExpand,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.inboxProvenanceMore,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// Stacked avatars for additional forwarders + circular `+N` overflow badge.
class _ProvenanceOverlappingRestAvatars extends StatelessWidget {
  const _ProvenanceOverlappingRestAvatars({
    required this.profiles,
    required this.overflowCount,
    required this.size,
    required this.overlap,
    required this.ringColor,
    required this.badgeFillColor,
    required this.badgeTextColor,
  });

  final List<Profile> profiles;
  final int overflowCount;
  final double size;
  final double overlap;
  final Color ringColor;
  final Color badgeFillColor;
  final Color badgeTextColor;

  @override
  Widget build(BuildContext context) {
    final extraSlots = overflowCount > 0 ? 1 : 0;
    final n = profiles.length + extraSlots;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final step = size - overlap;
    final width = size + (n - 1) * step;

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < profiles.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor),
                ),
                child: AvatarRated(
                  profile: profiles[i],
                  withRating: false,
                  size: size,
                ),
              ),
            ),
          if (overflowCount > 0)
            Positioned(
              left: profiles.length * step,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: badgeFillColor,
                  border: Border.all(color: ringColor),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$overflowCount',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: badgeTextColor,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProvenanceCollapsedQuote extends StatelessWidget {
  const _ProvenanceCollapsedQuote({
    required this.text,
    required this.borderColor,
  });

  final String text;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: borderColor, width: 2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          '"$text"',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ProvenanceSenderBlock extends StatelessWidget {
  const _ProvenanceSenderBlock({
    required this.profile,
    required this.notePreview,
    required this.borderColor,
    this.titleRowTrailing,
    this.noteTopSpacing = 6,
  });

  final Profile profile;
  final String notePreview;
  final Color borderColor;
  final Widget? titleRowTrailing;
  final double noteTopSpacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AvatarRated(
              profile: profile,
              withRating: false,
              size: _kProvenanceCollapsedAvatarSize,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                profile.title,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ?titleRowTrailing,
          ],
        ),
        if (notePreview.isNotEmpty) ...[
          SizedBox(height: noteTopSpacing),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: borderColor, width: 2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '"$notePreview"',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
