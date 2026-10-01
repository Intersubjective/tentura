import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_band.dart';
import 'package:tentura/features/closure/domain/entity/closure_draft_flag.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/entity/closure_result.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// «Итоги для тебя»: what the finalized closure meant for the viewer — the
/// author's outcome, the band, the draft flag — and the viewer's own
/// bookmarks. Shown on the request screen after finalize; renders nothing
/// while loading or when the server has no result for the viewer.
class ClosureResultCard extends StatefulWidget {
  const ClosureResultCard({
    required this.beaconId,
    required this.viewerId,
    required this.author,
    super.key,
  });

  final String beaconId;
  final String viewerId;
  final ClosureMember author;

  @override
  State<ClosureResultCard> createState() => _ClosureResultCardState();
}

class _ClosureResultCardState extends State<ClosureResultCard> {
  final _closureCase = GetIt.I<ClosureCase>();

  ClosureResult? _result;
  ClosureState? _state;
  Set<String> _marks = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = await _closureCase.fetchResultForViewer(widget.beaconId);
      if (result == null) return;
      final state = await _closureCase.fetchState(widget.beaconId);
      if (!mounted) return;
      setState(() {
        _result = result;
        _state = state;
        _marks = {...result.marks};
      });
    } on Object catch (e) {
      // The card is an extra on the request screen: stay hidden on failure.
      if (mounted) debugPrint('ClosureResultCard: $e');
    }
  }

  Future<void> _toggle(String id, {required bool on}) async {
    setState(() => on ? _marks.add(id) : _marks.remove(id));
    try {
      await _closureCase.setMark(
        beaconId: widget.beaconId,
        expectedEpoch: _state!.epoch,
        targetId: id,
        on: on,
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => on ? _marks.remove(id) : _marks.add(id));
      showSnackBar(context, text: e.toString(), isError: true, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final state = _state;
    if (result == null || state == null) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final people = [
      for (final m in [...state.members, widget.author])
        if (m.id != widget.viewerId) m,
    ].fold<Map<String, ClosureMember>>({}, (acc, m) => acc..[m.id] = m);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(TenturaSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.closureResultTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: TenturaSpacing.row),
            Text(
              _outcomeLine(l10n, result),
              style: theme.textTheme.bodyMedium,
            ),
            if (_bandLine(l10n, result) case final band?) ...[
              const SizedBox(height: TenturaSpacing.tight),
              Text(band, style: theme.textTheme.bodyMedium),
            ],
            if (_draftLine(l10n, result) case final draft?) ...[
              const SizedBox(height: TenturaSpacing.row),
              Text(
                draft,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: TenturaSpacing.section),
            Text(
              l10n.closureResultMarksTitle,
              style: theme.textTheme.labelLarge,
            ),
            for (final m in people.values)
              _MarkRow(
                name: m.displayName ?? m.id,
                marked: _marks.contains(m.id),
                onChanged: (on) => unawaited(_toggle(m.id, on: on)),
              ),
          ],
        ),
      ),
    );
  }

  /// notDone with no band means the member has no share in the results (V8);
  /// with a band (peer support, V6) the outcome line stands alone.
  static String _outcomeLine(L10n l10n, ClosureResult r) => switch (r.outcome) {
    ClosureOutcome.done => l10n.closureResultOutcomeDone,
    ClosureOutcome.notDone when r.band == ClosureBand.none =>
      l10n.closureResultNoShare,
    ClosureOutcome.notDone => l10n.closureResultOutcomeNotDone,
    ClosureOutcome.cantJudge => l10n.closureResultOutcomeCantJudge,
  };

  static String? _bandLine(L10n l10n, ClosureResult r) => switch (r.band) {
    ClosureBand.raised => l10n.closureResultBandRaised,
    ClosureBand.asIfSilent => l10n.closureResultBandAsIfSilent,
    ClosureBand.lowered => l10n.closureResultBandLowered,
    ClosureBand.none => null,
  };

  static String? _draftLine(L10n l10n, ClosureResult r) =>
      switch (r.draftFlag) {
        ClosureDraftFlag.notCounted => l10n.closureResultDraftNotCounted,
        ClosureDraftFlag.lastEditNotCounted => l10n.closureResultDraftLastEdit,
        ClosureDraftFlag.none => null,
      };
}

class _MarkRow extends StatelessWidget {
  const _MarkRow({
    required this.name,
    required this.marked,
    required this.onChanged,
  });

  final String name;
  final bool marked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Semantics(
          container: true,
          excludeSemantics: true,
          button: true,
          toggled: marked,
          label: l10n.closureAuthorBookmarkLabel(name),
          onTap: () => onChanged(!marked),
          child: IconButton(
            onPressed: () => onChanged(!marked),
            icon: Icon(marked ? Icons.bookmark : Icons.bookmark_border),
          ),
        ),
      ],
    );
  }
}
