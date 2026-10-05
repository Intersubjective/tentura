import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Opens the sheet where the baton author picks who takes it: «Pick for me»
/// (calls [onSelect] with `null`) and the people who can help, grouped by
/// priority (calls [onSelect] with that person's id). The sheet closes first.
Future<void> showRoomBatonChooseSheet(
  BuildContext context, {
  required List<RoomBatonCandidate> candidates,
  required void Function(String? userId) onSelect,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (ctx) => _ChooseSheet(
    candidates: candidates,
    onSelect: (userId) {
      Navigator.pop(ctx);
      onSelect(userId);
    },
  ),
);

class _ChooseSheet extends StatelessWidget {
  const _ChooseSheet({required this.candidates, required this.onSelect});

  final List<RoomBatonCandidate> candidates;
  final void Function(String? userId) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final showTiers = candidates.map((c) => c.tier).toSet().length > 1;
    final byTier = <int, List<RoomBatonCandidate>>{};
    for (final c in candidates) {
      if (c.response == RoomBatonResponse.canHelp) {
        byTier.putIfAbsent(c.tier, () => []).add(c);
      }
    }
    final tiers = byTier.keys.toList()..sort();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.casino_outlined),
            title: Text(l10n.batonPickForMe),
            subtitle: Text(l10n.batonPickForMeHint),
            onTap: () => onSelect(null),
          ),
          for (final tier in tiers) ...[
            if (showTiers)
              Padding(
                padding: EdgeInsets.only(
                  left: tt.screenHPadding,
                  top: tt.rowGap,
                  right: tt.screenHPadding,
                ),
                child: Text(
                  l10n.batonTierLabel(tier),
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ),
            for (final c in byTier[tier]!)
              ListTile(
                title: Text(c.title),
                onTap: () => onSelect(c.userId),
              ),
          ],
        ],
      ),
    );
  }
}
