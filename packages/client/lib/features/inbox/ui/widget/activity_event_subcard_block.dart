import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Compact activity-event previews nested under an offer or stream row.
class ActivityEventSubcardBlock extends StatefulWidget {
  const ActivityEventSubcardBlock({
    required this.eventTotal,
    required this.eventsPreview,
    required this.onMarkSeen,
    this.beaconId,
    super.key,
  });

  final int eventTotal;
  final List<AttentionReceipt> eventsPreview;
  final ValueChanged<String> onMarkSeen;

  /// When set, «ещё N» can load older children via [AttentionCase.activityAttention].
  final String? beaconId;

  @override
  State<ActivityEventSubcardBlock> createState() =>
      _ActivityEventSubcardBlockState();
}

class _ActivityEventSubcardBlockState extends State<ActivityEventSubcardBlock> {
  bool _expanded = false;
  bool _loadingMore = false;
  late List<AttentionReceipt> _events = List<AttentionReceipt>.of(
    widget.eventsPreview,
  );

  @override
  void didUpdateWidget(covariant ActivityEventSubcardBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded &&
        oldWidget.eventsPreview != widget.eventsPreview &&
        !_loadingMore) {
      _events = List<AttentionReceipt>.of(widget.eventsPreview);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty || widget.eventTotal <= 0) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleCap = context.windowClass == WindowClass.compact ? 1 : 3;
    final visible = _expanded
        ? _events
        : _events.take(visibleCap).toList(growable: false);
    final moreCount = widget.eventTotal - visible.length;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final bodyStyle = TenturaText.bodySmall(muted);
    final ageStyle = TenturaText.withTabular(
      TenturaText.bodySmall(tt.textFaint),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final receipt in visible) ...[
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap),
            child: _EventSubcard(
              receipt: receipt,
              bodyStyle: bodyStyle,
              ageStyle: ageStyle,
              l10n: l10n,
              onMarkSeen: () => widget.onMarkSeen(receipt.id),
            ),
          ),
        ],
        if (moreCount > 0)
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap, left: tt.cardGap),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TenturaTextAction(
                label: l10n.activityEventMore(moreCount),
                onPressed: _loadingMore ? null : () => unawaited(_expand()),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _expand() async {
    if (_expanded) {
      return;
    }
    setState(() => _expanded = true);
    final beaconId = widget.beaconId?.trim() ?? '';
    if (beaconId.isEmpty || _events.length >= widget.eventTotal) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await GetIt.I<AttentionCase>().activityAttention(
        beaconId: beaconId,
        limit: widget.eventTotal.clamp(1, 100),
      );
      if (!mounted) return;
      final seen = {for (final event in _events) event.id};
      final merged = [
        ..._events,
        for (final event in page.events)
          if (!seen.contains(event.id)) event,
      ];
      setState(() {
        _events = merged;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }
}

class _EventSubcard extends StatelessWidget {
  const _EventSubcard({
    required this.receipt,
    required this.bodyStyle,
    required this.ageStyle,
    required this.l10n,
    required this.onMarkSeen,
  });

  final AttentionReceipt receipt;
  final TextStyle bodyStyle;
  final TextStyle ageStyle;
  final L10n l10n;
  final VoidCallback onMarkSeen;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final copy = resolveUpdatesFeedRowCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
      l10n: l10n,
    );
    final glyph = updatesFeedGlyphFor(receipt, tt);
    final age = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final eventCopy = copy.headline.isNotEmpty ? copy.headline : copy.body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onMarkSeen,
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        child: TenturaTechCardStatic(
          surfaceOverride: tt.bg,
          borderOverride: tt.borderSubtle,
          radius: TenturaRadii.cardDense,
          padding: EdgeInsets.all(tt.cardGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: tt.avatarSize,
                child: Icon(
                  glyph.icon,
                  size: tt.iconSize,
                  color: glyph.color,
                ),
              ),
              SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: bodyStyle,
                    children: [
                      TextSpan(text: eventCopy),
                      TextSpan(text: ' · ', style: ageStyle),
                      TextSpan(text: age, style: ageStyle),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
