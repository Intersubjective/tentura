import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/ui/widget/compact_forwarder_avatars.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_card_deadline.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/inbox_provenance.dart';

Profile _senderProfile(InboxForwardSender s) => Profile(
      id: s.id,
      title: s.title,
      image: s.imageId != null && s.imageId!.isNotEmpty && s.imageId != 'null'
          ? ImageEntity(id: s.imageId!, authorId: s.id)
          : null,
    );

/// Collapsed: “Forwarded by” + mini avatars + chevron (no note text).
/// Expanded: per-sender name + avatar, then note (right-aligned) + vertical bar under avatar (full-width rows).
class InboxCardForwardsFold extends StatefulWidget {
  const InboxCardForwardsFold({
    required this.provenance,
    this.deadlineEndAt,
    super.key,
  });

  final InboxProvenance provenance;

  /// When set, a calendar-style due line (My Work status strip typography) on
  /// the same row as the forwarder control, left-aligned.
  final DateTime? deadlineEndAt;

  @override
  State<InboxCardForwardsFold> createState() => _InboxCardForwardsFoldState();
}

class _InboxCardForwardsFoldState extends State<InboxCardForwardsFold> {
  var _expanded = false;

  @override
  void didUpdateWidget(covariant InboxCardForwardsFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_provenanceEquivalent(oldWidget.provenance, widget.provenance)) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final senders = widget.provenance.senders;
    if (senders.isEmpty && widget.deadlineEndAt == null) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewerId = context.watch<ProfileCubit>().state.profile.id;

    final profiles = senders.map(_senderProfile).toList(growable: false);
    final rawOverflow =
        widget.provenance.totalDistinctSenders - senders.length;
    final overflow = rawOverflow > 0 ? rawOverflow : 0;

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final headerRight = senders.isEmpty
        ? null
        : Semantics(
            expanded: _expanded,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.translucent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.inboxForwardedByLabel,
                    style: labelStyle,
                  ),
                  const SizedBox(width: 6),
                  CompactForwarderAvatars(
                    profiles: profiles,
                    overflowCount: overflow,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          );

    final deadlineMeta =
        beaconCardCalendarDeadlineStatus(l10n, widget.deadlineEndAt);
    final baseDeadlineStyle = theme.textTheme.bodySmall!.copyWith(
      height: 1.15,
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final deadlineStyle = deadlineMeta != null && deadlineMeta.overdue
        ? baseDeadlineStyle.copyWith(
            color: scheme.error,
            fontWeight: FontWeight.w600,
          )
        : baseDeadlineStyle;
    final deadlineChild = deadlineMeta == null
        ? null
        : Text(
            deadlineMeta.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: deadlineStyle,
          );

    Widget headerRow() {
      final right = headerRight;
      if (deadlineChild == null && right == null) {
        return const SizedBox.shrink();
      }
      if (right == null) {
        return Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: deadlineChild,
              ),
            ),
          ],
        );
      }
      if (deadlineChild == null) {
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: right,
              ),
            ),
          ],
        );
      }
      return Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: deadlineChild,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: right,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headerRow(),
        if (_expanded) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < senders.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _SenderNoteBlock(
              sender: senders[i],
              l10n: l10n,
              theme: theme,
              scheme: scheme,
              viewerId: viewerId,
            ),
          ],
        ],
      ],
    );
  }
}

bool _provenanceEquivalent(InboxProvenance a, InboxProvenance b) {
  if (a.totalDistinctSenders != b.totalDistinctSenders) return false;
  if (a.senders.length != b.senders.length) return false;
  for (var i = 0; i < a.senders.length; i++) {
    final x = a.senders[i];
    final y = b.senders[i];
    if (x.id != y.id ||
        x.title != y.title ||
        x.notePreview != y.notePreview ||
        x.imageId != y.imageId) {
      return false;
    }
  }
  return true;
}

class _SenderNoteBlock extends StatelessWidget {
  const _SenderNoteBlock({
    required this.sender,
    required this.l10n,
    required this.theme,
    required this.scheme,
    required this.viewerId,
  });

  final InboxForwardSender sender;
  final L10n l10n;
  final ThemeData theme;
  final ColorScheme scheme;
  final String viewerId;

  @override
  Widget build(BuildContext context) {
    final profile = _senderProfile(sender);
    final displayName =
        SelfUserHighlight.displayName(l10n, profile, viewerId).trim();
    final note = sender.notePreview.trim();

    final header = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            displayName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 6),
        AvatarRated(
          profile: profile,
          size: 18,
          withRating: false,
        ),
      ],
    );

    if (note.isEmpty) {
      return Align(
        alignment: Alignment.centerRight,
        child: header,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        header,
        const SizedBox(height: 2),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Text(
                  note,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ),
              SizedBox(
                width: 18,
                child: Center(
                  child: Container(
                    width: 2,
                    height: double.infinity,
                    color: scheme.primary.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
