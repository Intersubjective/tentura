import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// «Facts to bring» (fact continuity §6.4): the source's readable [facts],
/// none ticked at first, at most [limit] ticks. «Select all» ticks the first
/// [limit] and says so when there are more. A lock marks facts only the
/// original's discussion could see. Reports the ticked ids, in list order,
/// through [onChanged]. Shared by the fork sheet and Post budding.
class FactsToBringChecklist extends StatefulWidget {
  const FactsToBringChecklist({
    required this.facts,
    required this.onChanged,
    super.key,
  });

  final List<BeaconFactCard> facts;

  final ValueChanged<List<String>> onChanged;

  /// Most facts one copy can bring.
  static const limit = 20;

  @override
  State<FactsToBringChecklist> createState() => _FactsToBringChecklistState();
}

class _FactsToBringChecklistState extends State<FactsToBringChecklist> {
  final _ticked = <String>{};
  bool _capped = false;

  void _set(Set<String> ids, {bool capped = false}) {
    setState(() {
      _ticked
        ..clear()
        ..addAll(ids);
      _capped = capped;
    });
    widget.onChanged([
      for (final f in widget.facts)
        if (_ticked.contains(f.id)) f.id,
    ]);
  }

  void _selectAll() => _set(
    {for (final f in widget.facts.take(FactsToBringChecklist.limit)) f.id},
    capped: widget.facts.length > FactsToBringChecklist.limit,
  );

  void _toggle(String id, bool tick) =>
      _set(tick ? {..._ticked, id} : ({..._ticked}..remove(id)));

  static bool _discussionOnly(BeaconFactCard fact) =>
      fact.visibility == BeaconFactCardVisibilityBits.room;

  @override
  Widget build(BuildContext context) {
    if (widget.facts.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final full = _ticked.length >= FactsToBringChecklist.limit;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.factsToBringTitle,
                style: TenturaText.titleSmall(tt.text),
              ),
            ),
            TextButton(
              onPressed: _selectAll,
              child: Text(l10n.factsToBringSelectAll),
            ),
          ],
        ),
        if (_capped)
          Text(
            l10n.factsToBringCapNotice(FactsToBringChecklist.limit),
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        for (final fact in widget.facts)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ticked.contains(fact.id),
            onChanged: full && !_ticked.contains(fact.id)
                ? null
                : (v) => _toggle(fact.id, v ?? false),
            title: Text(fact.factText),
            secondary: _discussionOnly(fact)
                ? Icon(Icons.lock_outline, color: tt.textMuted)
                : null,
          ),
        if (widget.facts.any(_discussionOnly))
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: tt.textMuted),
              SizedBox(width: tt.tightGap),
              Expanded(
                child: Text(
                  l10n.factsToBringLockLegend,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
