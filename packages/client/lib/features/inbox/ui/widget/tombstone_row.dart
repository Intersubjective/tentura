import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'activity_forward_outcome_copy.dart';

/// A tombstone: one compact row saying *something was here* (card spec §8).
///
/// It is deliberately **not** a card. It is a memory of an act the viewer or
/// somebody else performed — so it speaks in the past tense, carries no dot,
/// no relation chip and no sub-cards, never bumps and is excluded from
/// grouping (E2 as amended by A1/A2). The one gesture it owns is the private
/// ×: a tombstone is already answered, nobody waits on it, so removing it is
/// a private act and never a social one.
class TombstoneRow extends StatelessWidget {
  const TombstoneRow({
    required this.receipt,
    required this.onOpenBeacon,
    required this.onDismiss,
    this.forwarder,
    this.onRestore,
    super.key,
  });

  /// The whole ≥48 dp × target.
  static const dismissKey = Key('tombstone-row-dismiss');

  /// «Вернуть» — `notInterested` only.
  static const restoreKey = Key('tombstone-row-restore');

  final AttentionReceipt receipt;

  /// The last forwarder, whose avatar leads the row. The paper-plane glyph the
  /// old row used is a *send* affordance and misread as "I sent this".
  final Profile? forwarder;

  final VoidCallback onOpenBeacon;

  /// E7 semantics — `seen_at` as dismissed. Wired by the surface.
  final VoidCallback onDismiss;

  /// Re-pins the forward. Rendered only for `notInterested`.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final profile = forwarder;
    final name = profile?.shownName.trim() ?? '';
    // Title, then who it came from, then what you did — the order of the
    // Request cards around it, without the quotes they no longer wear.
    final headline = receipt.title;
    final from = name.isEmpty ? null : l10n.constellationPreviewAuthorLine(name);
    final sentence = activityForwardOutcomeLabel(l10n, receipt.forwardOutcome);
    final localCreatedAt = receipt.createdAt.toLocal();
    final age = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';

    return Semantics(
      // The whole sentence, so the outcome is never carried by chrome alone
      // (§11).
      label: [headline, from, sentence].nonNulls.join(', '),
      excludeSemantics: false,
      selected: TenturaListDetailSelection.of(context) == receipt.beaconId,
      child: Material(
        // Material 3 list-detail: the Request open beside this list.
        color: TenturaListDetailSelection.of(context) == receipt.beaconId
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        child: InkWell(
          onTap: onOpenBeacon,
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The frame is kept even without a resolved forwarder, so a
                // list of tombstones keeps one text column.
                // A neutral glyph rather than blank space: an empty 36-44 dp
                // square read as a missing picture.
                profile == null
                    ? _NoForwarderGlyph(size: tt.avatarSize)
                    : TenturaAvatar.medium(profile: profile),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The title keeps the lion's share; the age is
                          // flexible and ellipsises, because an absolute date
                          // at 2x text is wide enough to push the row into
                          // overflow on a 360 dp screen.
                          Expanded(
                            flex: 4,
                            child: Text(
                              headline,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TenturaText.titleSmall(
                                tt.text,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          SizedBox(width: tt.iconTextGap),
                          // The age keeps its own width ("80d ago" was cut to
                          // "80d …" while the title had room), capped so a
                          // long absolute date at 2x text still fits 360 dp.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: tt.avatarSize * 3,
                            ),
                            child: Tooltip(
                              message: absoluteTime,
                              excludeFromSemantics: true,
                              child: Text(
                                age,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.withTabular(
                                  TenturaText.bodySmall(tt.textMuted),
                                ),
                                semanticsLabel: '',
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (from != null)
                        Text(
                          from,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                      if (sentence != null) ...[
                        SizedBox(height: tt.tightGap),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sentence,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            ),
                            if (receipt.forwardOutcome ==
                                AttentionForwardOutcome.notInterested)
                              TenturaTextAction(
                                key: TombstoneRow.restoreKey,
                                label: l10n.activityForwardRestore,
                                onPressed: onRestore,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Beside the whole text block, not inside the title line: a
                // 48 dp target in that line pushed the outcome sentence ~28 dp
                // below its title.
                SizedBox(width: tt.tightGap),
                Transform.translate(
                  offset: Offset(0, -tt.cardPadding.top / 2),
                  child: _DismissControl(
                    label: l10n.attentionEventDismiss,
                    onPressed: onDismiss,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoForwarderGlyph extends StatelessWidget {
  const _NoForwarderGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Icon(
          Icons.campaign_outlined,
          size: tt.iconSize * 0.8,
          color: tt.textMuted,
        ),
      ),
    );
  }
}

class _DismissControl extends StatelessWidget {
  const _DismissControl({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SizedBox(
      key: TombstoneRow.dismissKey,
      width: kMinInteractiveDimension,
      height: kMinInteractiveDimension,
      child: IconButton(
        onPressed: onPressed,
        tooltip: label,
        iconSize: tt.iconSize,
        padding: EdgeInsets.zero,
        color: tt.textFaint,
        icon: Icon(Icons.close, semanticLabel: label),
      ),
    );
  }
}
