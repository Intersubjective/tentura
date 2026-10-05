import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Most people one «Who'll take it?» baton can ask.
const kBatonMaxCandidates = 12;

/// Opens the sheet where the author picks [participants] to ask «Who'll take
/// it?» (optionally with a 1/2/3 priority each). The sheet closes first, then
/// [onAsk] gets `[{userId, tier}]`.
Future<void> showRoomBatonCreateSheet(
  BuildContext context, {
  required List<BeaconParticipant> participants,
  required void Function(List<({String userId, int tier})> candidates) onAsk,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (ctx) => _CreateSheet(
    participants: participants,
    onAsk: (candidates) {
      Navigator.pop(ctx);
      onAsk(candidates);
    },
  ),
);

class _CreateSheet extends StatefulWidget {
  const _CreateSheet({required this.participants, required this.onAsk});

  final List<BeaconParticipant> participants;
  final void Function(List<({String userId, int tier})> candidates) onAsk;

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _tiers = <String, int>{};
  var _setPriority = false;

  bool get _canAsk => _tiers.isNotEmpty && _tiers.length <= kBatonMaxCandidates;

  void _ask() {
    if (!_canAsk) return;
    widget.onAsk([
      for (final p in widget.participants)
        if (_tiers.containsKey(p.userId))
          (userId: p.userId, tier: _setPriority ? _tiers[p.userId]! : 1),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: Text(
              l10n.batonCreateTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.rowGap,
            ),
            child: Text(
              l10n.batonCreateHint,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in widget.participants)
                  CheckboxListTile(
                    value: _tiers.containsKey(p.userId),
                    onChanged: (picked) => setState(() {
                      if (picked ?? false) {
                        _tiers[p.userId] = 1;
                      } else {
                        _tiers.remove(p.userId);
                      }
                    }),
                    title: Text(p.displayLabel(l10n.unknownPerson)),
                    subtitle: _setPriority && _tiers.containsKey(p.userId)
                        ? Padding(
                            padding: EdgeInsets.only(top: tt.rowGap),
                            child: SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(value: 1, label: Text('1')),
                                ButtonSegment(value: 2, label: Text('2')),
                                ButtonSegment(value: 3, label: Text('3')),
                              ],
                              selected: {_tiers[p.userId]!},
                              onSelectionChanged: (s) =>
                                  setState(() => _tiers[p.userId] = s.first),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
          SwitchListTile(
            value: _setPriority,
            onChanged: (v) => setState(() => _setPriority = v),
            title: Text(l10n.batonCreateTiersToggle),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
            child: FilledButton(
              onPressed: _canAsk ? _ask : null,
              child: Text(l10n.batonCreateSubmit),
            ),
          ),
        ],
      ),
    );
  }
}
