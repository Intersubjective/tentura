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

/// Compact activity-event previews nested under an offer or stream row.
class ActivityEventSubcardBlock extends StatefulWidget {
  const ActivityEventSubcardBlock({
    required this.eventTotal,
    required this.eventsPreview,
    required this.onMarkSeen,
    this.actors = const {},
    this.beaconId,
    super.key,
  });

  final int eventTotal;
  final List<AttentionReceipt> eventsPreview;
  final ValueChanged<String> onMarkSeen;

  /// Actor profiles keyed by user id (from owning cubit).
  final Map<String, Profile> actors;

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
              onTap: () => widget.onMarkSeen(receipt.id),
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
                    TenturaTextAction(
                      label: l10n.activityEventMore(moreCount),
                      onPressed: _loadingMore
                          ? null
                          : () => unawaited(_expand()),
                    ),
                  if (_expanded)
                    TenturaTextAction(
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
      final missingIds = attentionActorIds(merged).difference(_actors.keys.toSet());
      var actors = _actors;
      if (missingIds.isNotEmpty) {
        final resolved =
            await GetIt.I<AttentionActorProfilesCase>().resolve(missingIds);
        if (!mounted) return;
        actors = {..._actors, ...resolved};
      }
      setState(() {
        _events = merged;
        _actors = actors;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }
}
