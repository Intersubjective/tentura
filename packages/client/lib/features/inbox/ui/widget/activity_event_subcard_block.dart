import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_actor_ids.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// What the overflow control does when more events exist than the preview
/// shows.
enum AttentionBlockOverflowPolicy {
  /// «ещё N» opens the Request's Timeline and the block never grows
  /// (D-171-5b) — this is what gives a card a hard maximum height.
  timeline,

  /// The block expands in place and pages through children with a cursor
  /// (D10) — for surfaces that are not height-bound.
  paginate,
}

/// Compact activity-event previews nested under an offer or stream row.
class ActivityEventSubcardBlock extends StatefulWidget {
  const ActivityEventSubcardBlock({
    required this.eventTotal,
    required this.eventsPreview,
    this.onClearEvent,
    this.onEventTap,
    this.onOpenTimeline,
    this.actors = const {},
    this.beaconId,
    this.overflowPolicy = AttentionBlockOverflowPolicy.timeline,
    this.pageSize = 20,
    super.key,
  });

  /// Expands / loads the next page. Only present under
  /// [AttentionBlockOverflowPolicy.paginate].
  static const loadMoreKey = Key('attention-block-load-more');

  static const collapseKey = Key('attention-block-collapse');

  /// «ещё N» under [AttentionBlockOverflowPolicy.timeline] — opens the
  /// Timeline, never expands.
  static const moreKey = Key('attention-block-more');

  final int eventTotal;
  final List<AttentionReceipt> eventsPreview;
  /// Clears one event (the clear axis, D02/U10b) — never `markSeen`.
  final ValueChanged<String>? onClearEvent;

  final ValueChanged<AttentionReceipt>? onEventTap;

  /// Opens the Request's Timeline. Under the `timeline` policy this is what
  /// «ещё N» does (D-171-5b).
  final VoidCallback? onOpenTimeline;

  /// Actor profiles keyed by user id (from owning cubit).
  final Map<String, Profile> actors;

  /// When set, older children load via [AttentionCase.activityAttention].
  final String? beaconId;

  final AttentionBlockOverflowPolicy overflowPolicy;

  /// Rows per cursor page. The old block asked for `min(eventTotal, 100)` in
  /// one request and could never reach the 101st child.
  final int pageSize;

  @override
  State<ActivityEventSubcardBlock> createState() =>
      _ActivityEventSubcardBlockState();
}

class _ActivityEventSubcardBlockState extends State<ActivityEventSubcardBlock> {
  bool _expanded = false;
  bool _loadingMore = false;
  String? _nextCursor;
  bool _exhausted = false;
  late List<AttentionReceipt> _events = List<AttentionReceipt>.of(
    widget.eventsPreview,
  );
  late Map<String, Profile> _actors = Map<String, Profile>.of(widget.actors);

  @override
  void didUpdateWidget(covariant ActivityEventSubcardBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_expanded &&
        oldWidget.eventsPreview != widget.eventsPreview &&
        !_loadingMore) {
      _events = List<AttentionReceipt>.of(widget.eventsPreview);
    }
    if (oldWidget.actors != widget.actors) {
      _actors = {
        ..._actors,
        ...widget.actors,
      };
    }
  }

  /// Obligations first, then the rest in the order the owner supplied (D10).
  /// Stable within each group, so a preview never reshuffles on rebuild.
  List<AttentionReceipt> get _ordered => [
    ..._events.where((e) => e.isLiveObligation),
    ..._events.where((e) => !e.isLiveObligation),
  ];

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty || widget.eventTotal <= 0) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final visibleCap = context.windowClass == WindowClass.compact ? 1 : 3;
    final ordered = _ordered;
    final visible = _expanded
        ? ordered
        : ordered.take(visibleCap).toList(growable: false);
    // Server total, never the loaded-row count: a page that has not arrived
    // must not shrink the number the user reads.
    final moreCount = widget.eventTotal - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final receipt in visible)
          Padding(
            key: ValueKey(receipt.id),
            padding: EdgeInsets.only(top: tt.tightGap),
            child: AttentionMiniCard(
              receipt: receipt,
              actor: _actorFor(receipt),
              onTap: widget.onEventTap == null
                  ? null
                  : () => widget.onEventTap!(receipt),
              onDismiss: widget.onClearEvent == null
                  ? null
                  : () => _clear(receipt.id),
            ),
          ),
        if (moreCount > 0 || _expanded)
          Padding(
            padding: EdgeInsets.only(top: tt.tightGap, left: tt.cardGap),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: tt.rowGap,
                children: [
                  if (moreCount > 0)
                    switch (widget.overflowPolicy) {
                      // D-171-5b: the card's hard maximum height is exactly
                      // this — «ещё N» leaves for the Timeline instead of
                      // growing the block.
                      AttentionBlockOverflowPolicy.timeline =>
                        TenturaTextAction(
                          key: ActivityEventSubcardBlock.moreKey,
                          label: l10n.activityEventMore(moreCount),
                          onPressed: widget.onOpenTimeline,
                        ),
                      AttentionBlockOverflowPolicy.paginate =>
                        TenturaTextAction(
                          key: ActivityEventSubcardBlock.loadMoreKey,
                          label: l10n.activityEventMore(moreCount),
                          onPressed: _loadingMore
                              ? null
                              : () => unawaited(_expand()),
                        ),
                    },
                  if (_expanded)
                    TenturaTextAction(
                      key: ActivityEventSubcardBlock.collapseKey,
                      label: l10n.inboxProvenanceCollapse,
                      onPressed: _collapse,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Profile? _actorFor(AttentionReceipt receipt) {
    final id = receipt.actorUserId?.trim() ?? '';
    if (id.isEmpty) return null;
    return _actors[id];
  }

  void _collapse() => setState(() => _expanded = false);

  /// The mini-card has already finished its removal animation (E32), so the
  /// row may leave the tree now.
  void _clear(String receiptId) {
    setState(() => _events.removeWhere((e) => e.id == receiptId));
    widget.onClearEvent?.call(receiptId);
  }

  Future<void> _expand() async {
    if (!_expanded) {
      setState(() => _expanded = true);
      // Everything already in hand: showing it is the whole step.
      if (_events.length >= widget.eventTotal) return;
    }
    await _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    final beaconId = widget.beaconId?.trim() ?? '';
    if (beaconId.isEmpty ||
        _loadingMore ||
        _exhausted ||
        _events.length >= widget.eventTotal) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final page = await GetIt.I<AttentionCase>().activityAttention(
        beaconId: beaconId,
        cursor: _nextCursor,
        limit: widget.pageSize,
      );
      if (!mounted) return;
      final seen = {for (final event in _events) event.id};
      final merged = [
        ..._events,
        for (final event in page.events)
          if (!seen.contains(event.id)) event,
      ];
      final missingIds = attentionActorIds(
        merged,
      ).difference(_actors.keys.toSet());
      var actors = _actors;
      if (missingIds.isNotEmpty) {
        final resolved = await GetIt.I<AttentionActorProfilesCase>().resolve(
          missingIds,
        );
        if (!mounted) return;
        actors = {..._actors, ...resolved};
      }
      final cursor = page.nextCursor?.trim() ?? '';
      setState(() {
        _events = merged;
        _actors = actors;
        _nextCursor = cursor.isEmpty ? null : cursor;
        // A page that ends without a cursor is the last one; without this the
        // control would keep asking for a page that can never arrive.
        _exhausted = cursor.isEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }
}
