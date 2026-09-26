import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Max characters shown in the collapsed one-line excerpt before an ellipsis.
const int kRoomMessageFactQuoteCollapsedMaxChars = 80;

String _collapsedExcerpt(String text) {
  final trimmed = text.trim();
  if (trimmed.length <= kRoomMessageFactQuoteCollapsedMaxChars) return trimmed;
  return '${trimmed.substring(0, kRoomMessageFactQuoteCollapsedMaxChars).trimRight()}…';
}

/// Quoted fact snapshot inside a room message bubble (issue #181 plan
/// §7.5/§7.6): collapsed to a one-line excerpt by default, tap to expand in
/// place to the full quoted text. Flags drift from the fact's current head
/// ("Changed since quoted") and permanent unpin, without ever substituting
/// the fact's live wording for the snapshot quoted at send time.
class RoomMessageFactQuote extends StatefulWidget {
  const RoomMessageFactQuote({
    required this.quotedFact,
    this.currentFact,
    this.onOpen,
    this.onOpenHistory,
    super.key,
  });

  final QuotedFact quotedFact;

  /// The fact's live state, if still available to the viewer. Never used to
  /// render the quote's text — only the snapshot in [quotedFact] is shown.
  final BeaconFactCard? currentFact;

  final VoidCallback? onOpen;
  final VoidCallback? onOpenHistory;

  @override
  State<RoomMessageFactQuote> createState() => _RoomMessageFactQuoteState();
}

class _RoomMessageFactQuoteState extends State<RoomMessageFactQuote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final quoted = widget.quotedFact;
    final unpinned = quoted.isUnpinned;
    final showFull = _expanded || unpinned;
    // The snapshot's currentSeq is only as fresh as the message fetch; a fact
    // edit refreshes the room's fact list, not the messages.
    final changedSinceQuoted =
        quoted.isChangedSinceQuoted ||
        (widget.currentFact?.revisionSeq ?? 0) > quoted.seq;
    final textColor = unpinned ? scheme.onSurfaceVariant : scheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            showFull ? quoted.factText : _collapsedExcerpt(quoted.factText),
            style: TenturaText.bodySmall(textColor),
            maxLines: showFull ? null : 1,
            overflow: showFull ? null : TextOverflow.ellipsis,
          ),
          if (unpinned)
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              child: Text(
                l10n.beaconRoomFactQuoteUnpinned,
                style: TenturaText.status(scheme.onSurfaceVariant),
              ),
            ),
          if (changedSinceQuoted)
            Padding(
              padding: EdgeInsets.only(top: tt.tightGap),
              // Wraps in a narrow bubble instead of overflowing.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: tt.iconTextGap / 2,
                children: [
                  Text(
                    l10n.beaconRoomFactQuoteChangedSinceQuoted,
                    style: TenturaText.status(scheme.onSurfaceVariant),
                  ),
                  TextButton(
                    key: const ValueKey('room-fact-quote-diff'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: widget.onOpenHistory,
                    child: Text(l10n.beaconRoomFactQuoteDiff),
                  ),
                ],
              ),
            ),
          if (!unpinned && _expanded)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: widget.onOpen,
                child: Text(l10n.beaconRoomFactQuoteOpen),
              ),
            ),
        ],
      ),
    );
  }
}
