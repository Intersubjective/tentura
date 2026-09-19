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
    final headline = name.isEmpty
        ? l10n.attentionCardQuotedTitle(receipt.title)
        : l10n.attentionCardTitleByForwarder(receipt.title, name);
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
      label: [headline, sentence].nonNulls.join(', '),
      excludeSemantics: false,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenBeacon,
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The frame is kept even without a resolved forwarder, so a
                // list of tombstones keeps one text column.
                profile == null
                    ? SizedBox.square(dimension: tt.avatarSize)
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
                          Flexible(
                            child: Tooltip(
                              message: absoluteTime,
                              excludeFromSemantics: true,
                              child: Text(
                                age,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.withTabular(
                                  TenturaText.bodySmall(tt.textFaint),
                                ),
                                semanticsLabel: '',
                              ),
                            ),
                          ),
                          SizedBox(width: tt.tightGap),
                          _DismissControl(
                            label: l10n.attentionEventDismiss,
                            onPressed: onDismiss,
                          ),
                        ],
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
              ],
            ),
          ),
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
