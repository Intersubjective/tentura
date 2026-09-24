import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// The one entry point to a Request's attention timeline (§9).
///
/// Every attention surface's `onOpenTimeline` lands here. Before U17b they
/// disagreed: For You's pinned card and My Desk pushed the Request detail,
/// while For You's stream card went through `openFromUpdate`, whose
/// destination map can route a receipt to a profile or the review screen
/// entirely. "Show me what happened on this Request" was three different
/// answers depending on which control you pressed.
///
/// §9: the timeline "shows what happened on that Request, including the
/// viewer's own authorized receipt history" — which is exactly what
/// `AttentionCase.requestHistory` returns, and which had no UI caller at all
/// until now.
Future<void> showRequestAttentionTimelineSheet(
  BuildContext context, {
  required String beaconId,
}) => showTenturaAdaptiveSheet<void>(
  context: context,
  builder: (_) => RequestAttentionTimelineSheet(beaconId: beaconId),
);

class RequestAttentionTimelineSheet extends StatefulWidget {
  const RequestAttentionTimelineSheet({
    required this.beaconId,
    super.key,
  });

  static const pageSize = 20;

  final String beaconId;

  @override
  State<RequestAttentionTimelineSheet> createState() =>
      _RequestAttentionTimelineSheetState();
}

class _RequestAttentionTimelineSheetState
    extends State<RequestAttentionTimelineSheet> {
  final _scrollController = ScrollController();
  final _items = <AttentionReceipt>[];

  String? _cursor;
  var _loading = true;
  var _loadingMore = false;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 48) return;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loadingMore) return;
    if (_items.isNotEmpty && _cursor == null) return;
    _loadingMore = true;
    try {
      final page = await GetIt.I<AttentionCase>().requestHistory(
        beaconId: widget.beaconId,
        cursor: _cursor,
        limit: RequestAttentionTimelineSheet.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _cursor = page.nextCursor;
        _loading = false;
        _failed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final maxH = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.tightGap * 2,
            tt.screenHPadding,
            tt.rowGap,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.labelTimeline,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: tt.rowGap),
              Flexible(child: _body(l10n, tt)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(L10n l10n, TenturaTokens tt) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_failed && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: tt.cardPadding,
          child: Text(
            l10n.updatesRefreshFailedBanner,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: tt.cardPadding,
          child: Text(
            l10n.updatesEmptyAllHint,
            textAlign: TextAlign.center,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      itemCount: _items.length,
      itemBuilder: (context, index) => _RequestTimelineRow(
        receipt: _items[index],
      ),
    );
  }
}

/// One timeline row.
///
/// §8a — "Object headlines on For You, event headlines in History". The
/// timeline is a chronological receipt log, so it speaks the History voice:
/// the same resolver the Updates feed uses, not the Request's own title.
class _RequestTimelineRow extends StatelessWidget {
  const _RequestTimelineRow({required this.receipt});

  final AttentionReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
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

    return Semantics(
      identifier: TestIds.updatesReceipt(receipt.id),
      child: Padding(
        padding: tt.listRowPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(glyph.icon, size: 18, color: glyph.color),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          copy.headline,
                          style: TenturaText.titleSmall(tt.text),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: tt.iconTextGap),
                      Text(
                        age,
                        style: TenturaText.withTabular(
                          TenturaText.bodySmall(tt.textFaint),
                        ),
                      ),
                    ],
                  ),
                  if (copy.body.isNotEmpty)
                    Text(
                      copy.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
