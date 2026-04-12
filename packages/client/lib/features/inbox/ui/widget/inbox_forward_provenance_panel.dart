import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../../domain/entity/inbox_provenance.dart';

/// Matches mock `w-5 h-5` (20px) for collapsed provenance avatars.
const _kAvatarSize = 20.0;

/// Negative overlap between stacked forwarder avatars (`-space-x-1.5` in mock).
const _kAvatarOverlap = 6.0;

Profile _senderProfile(InboxForwardSender s) => Profile(
      id: s.id,
      title: s.title,
      image: s.imageId != null && s.imageId!.isNotEmpty && s.imageId != 'null'
          ? ImageEntity(id: s.imageId!, authorId: s.id)
          : null,
    );

/// Note preview for the primary (MR-ranked) forwarder; used when provenance is collapsed.
String _collapsedPreviewText(InboxProvenance p, String latestNotePreview) {
  if (p.senders.isNotEmpty) {
    final n = p.senders.first.notePreview;
    if (n.isNotEmpty) return n;
  }
  if (p.strongestNotePreview.isNotEmpty) return p.strongestNotePreview;
  return latestNotePreview;
}

/// More than one distinct forwarder — only then may the user expand/collapse.
bool _canExpand(InboxProvenance p) {
  if (p.senders.isEmpty) return false;
  return p.senders.length > 1 || (p.totalDistinctSenders - p.senders.length) > 0;
}

/// Inbox card forward trail + notes (same UI as beacon view “Forwards” tab).
class InboxForwardProvenancePanel extends StatefulWidget {
  const InboxForwardProvenancePanel({
    required this.provenance,
    this.latestNotePreview = '',
    super.key,
  });

  final InboxProvenance provenance;
  final String latestNotePreview;

  @override
  State<InboxForwardProvenancePanel> createState() =>
      _InboxForwardProvenancePanelState();
}

class _InboxForwardProvenancePanelState extends State<InboxForwardProvenancePanel> {
  var _expanded = false;

  @override
  void didUpdateWidget(covariant InboxForwardProvenancePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canExpand(widget.provenance) && _expanded) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = widget.provenance;
    if (p.senders.isEmpty) {
      return const SizedBox.shrink();
    }

    final overflow = p.totalDistinctSenders - p.senders.length;
    final showOverflow = overflow > 0;
    final canExpand = _canExpand(p);

    return GestureDetector(
      onTap: canExpand
          ? () => setState(() => _expanded = !_expanded)
          : null,
      behavior: HitTestBehavior.translucent,
      child: Semantics(
        expanded: canExpand && _expanded,
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
                if (!canExpand) ...[
                  _ProvenanceCollapsedHeader(
                    primaryProfile: _senderProfile(p.senders.first),
                    primaryName: p.senders.first.title,
                    restProfiles: [
                      for (var i = 1; i < p.senders.length; i++)
                        _senderProfile(p.senders[i]),
                    ],
                    overflowCount: showOverflow ? overflow : 0,
                    showExpandAction: false,
                    onExpand: () {},
                  ),
                  const SizedBox(height: kSpacingSmall),
                  _ProvenanceCollapsedQuote(
                    text: _collapsedPreviewText(
                      p,
                      widget.latestNotePreview,
                    ),
                    borderColor: scheme.primaryFixedDim,
                  ),
                ] else ...[
                  if (!_expanded)
                    _ProvenanceCollapsedHeader(
                      primaryProfile: _senderProfile(p.senders.first),
                      primaryName: p.senders.first.title,
                      restProfiles: [
                        for (var i = 1; i < p.senders.length; i++)
                          _senderProfile(p.senders[i]),
                      ],
                      overflowCount: showOverflow ? overflow : 0,
                      showExpandAction: true,
                      onExpand: () => setState(() => _expanded = true),
                    ),
                  if (_expanded)
                    Semantics(
                      label: l10n.inboxProvenanceTrail,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < p.senders.length; i++) ...[
                            if (i > 0) const SizedBox(height: kSpacingMedium),
                            _ProvenanceSenderBlock(
                              profile: _senderProfile(p.senders[i]),
                              notePreview: p.senders[i].notePreview,
                              borderColor: i == 0
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                              titleRowTrailing: i == 0
                                  ? TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        foregroundColor: scheme.primary,
                                      ),
                                      onPressed: () =>
                                          setState(() => _expanded = false),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            l10n.inboxProvenanceCollapse,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
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
                              noteTopSpacing: i == 0 ? kSpacingSmall : 6,
                            ),
                          ],
                          if (showOverflow) ...[
                            const SizedBox(height: kSpacingSmall),
                            Text(
                              l10n.inboxMoreForwarders(overflow),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (!_expanded) ...[
                    const SizedBox(height: kSpacingSmall),
                    _ProvenanceCollapsedQuote(
                      text: _collapsedPreviewText(
                        p,
                        widget.latestNotePreview,
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
                  size: _kAvatarSize,
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
                  size: _kAvatarSize,
                  overlap: _kAvatarOverlap,
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
              size: _kAvatarSize,
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
