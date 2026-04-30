import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/fact_actions_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

enum _FactsFilter { all, active, corrected }

String _shortUserId(String id) =>
    id.length <= 12 ? id : '${id.substring(0, 10)}…';

String _pinnedByName(List<BeaconParticipant> participants, String userId) {
  for (final p in participants) {
    if (p.userId == userId) {
      return _shortUserId(userId);
    }
  }
  return _shortUserId(userId);
}

List<BeaconFactCard> _filterFacts(List<BeaconFactCard> raw, _FactsFilter f) {
  final list = [...raw]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  switch (f) {
    case _FactsFilter.all:
      return list;
    case _FactsFilter.active:
      return list
          .where((e) => e.status == BeaconFactCardStatusBits.active)
          .toList();
    case _FactsFilter.corrected:
      return list
          .where((e) => e.status == BeaconFactCardStatusBits.corrected)
          .toList();
  }
}

/// Lists pinned facts with filters and per-row actions.
Future<void> showRoomFactsSheet(
  BuildContext context, {
  required RoomCubit cubit,
  required List<BeaconParticipant> participants,
  String? initialFocusFactId,
}) {
  final l10n = L10n.of(context)!;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (ctx, scrollController) => BlocBuilder<RoomCubit, RoomState>(
        bloc: cubit,
        builder: (context, state) => _RoomFactsBody(
          cubit: cubit,
          facts: state.factCards,
          participants: participants,
          l10n: l10n,
          scrollController: scrollController,
          initialFocusFactId: initialFocusFactId,
        ),
      ),
    ),
  );
}

class _RoomFactsBody extends StatefulWidget {
  const _RoomFactsBody({
    required this.cubit,
    required this.facts,
    required this.participants,
    required this.l10n,
    required this.scrollController,
    this.initialFocusFactId,
  });

  final RoomCubit cubit;

  final List<BeaconFactCard> facts;

  final List<BeaconParticipant> participants;

  final L10n l10n;

  final ScrollController scrollController;

  final String? initialFocusFactId;

  @override
  State<_RoomFactsBody> createState() => _RoomFactsBodyState();
}

class _RoomFactsBodyState extends State<_RoomFactsBody> {
  _FactsFilter _filter = _FactsFilter.all;

  final Map<String, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    final fid = widget.initialFocusFactId;
    if (fid != null && fid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToFactAsync(fid));
      });
    }
  }

  Future<void> _scrollToFactAsync(String fid) async {
    final k = _rowKeys[fid]?.currentContext;
    if (k != null && mounted) {
      await Scrollable.ensureVisible(
        k,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    }
  }

  GlobalKey _keyForRow(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final filtered = _filterFacts(widget.facts, _filter);

    return SafeArea(
      child: Padding(
        padding: kPaddingH.add(kPaddingSmallT),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.l10n.beaconFactsSheetTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: tt.rowGap),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(widget.l10n.beaconRoomFactsFilterAll),
                    selected: _filter == _FactsFilter.all,
                    onSelected: (_) => setState(() => _filter = _FactsFilter.all),
                  ),
                  SizedBox(width: tt.rowGap),
                  FilterChip(
                    label: Text(widget.l10n.beaconRoomFactsFilterActive),
                    selected: _filter == _FactsFilter.active,
                    onSelected: (_) =>
                        setState(() => _filter = _FactsFilter.active),
                  ),
                  SizedBox(width: tt.rowGap),
                  FilterChip(
                    label: Text(widget.l10n.beaconRoomFactsFilterCorrected),
                    selected: _filter == _FactsFilter.corrected,
                    onSelected: (_) =>
                        setState(() => _filter = _FactsFilter.corrected),
                  ),
                ],
              ),
            ),
            SizedBox(height: tt.rowGap),
            if (filtered.isEmpty)
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    widget.facts.isEmpty
                        ? widget.l10n.beaconFactsSheetEmpty
                        : widget.l10n.beaconRoomFactsFilteredEmpty,
                    style: TenturaText.body(tt.textMuted),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: widget.scrollController,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final f = filtered[index];
                    final isPublic =
                        f.visibility == BeaconFactCardVisibilityBits.public;
                    final corrected =
                        f.status == BeaconFactCardStatusBits.corrected;
                    final when =
                        '${dateFormatYMD(f.createdAt)} · ${timeFormatHm(f.createdAt)}';
                    final pinner = widget.l10n.beaconRoomFactCardPinnedByLabel(
                      _pinnedByName(widget.participants, f.pinnedBy),
                    );
                    return Card(
                      key: _keyForRow(f.id),
                      margin: EdgeInsets.only(bottom: tt.rowGap),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => unawaited(
                          showFactActionsSheet(context, cubit: widget.cubit, fact: f),
                        ),
                        child: Padding(
                          padding: kPaddingSmallH.add(
                            const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Chip(
                                    label: Text(
                                      isPublic
                                          ? widget.l10n.beaconRoomPinFactPublic
                                          : widget
                                              .l10n.beaconRoomPinFactRoomOnly,
                                      style:
                                          Theme.of(context).textTheme.labelSmall,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  ),
                                  if (corrected) ...[
                                    SizedBox(width: tt.rowGap / 2),
                                    Chip(
                                      label: Text(
                                        widget
                                            .l10n.beaconRoomFactCardCorrectedBadge,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                  const Spacer(),
                                  Text(
                                    when,
                                    style: TenturaText.bodySmall(tt.textMuted),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.more_vert),
                                    onPressed: () => unawaited(
                                      showFactActionsSheet(
                                        context,
                                        cubit: widget.cubit,
                                        fact: f,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SelectableText(
                                f.factText,
                                style: TenturaText.body(tt.text),
                              ),
                              SizedBox(height: tt.rowGap / 2),
                              Text(
                                pinner,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
