import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'room_baton_card.dart';

/// Opens the sheet where the baton author picks who takes it: «Pick for me»
/// (calls [onSelect] with `null`) and the people who can help, grouped by
/// priority (calls [onSelect] with that person's id). The sheet closes first.
Future<void> showRoomBatonChooseSheet(
  BuildContext context, {
  required List<RoomBatonAuthorRow> rows,
  required void Function(String? userId) onSelect,
  List<BeaconParticipant> participants = const [],
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useRootNavigator: true,
  isScrollControlled: true,
  builder: (ctx) => _ChooseSheet(
    rows: rows,
    participants: participants,
    onSelect: (userId) {
      Navigator.pop(ctx);
      onSelect(userId);
    },
  ),
);

class _ChooseSheet extends StatelessWidget {
  const _ChooseSheet({
    required this.rows,
    required this.onSelect,
    required this.participants,
  });

  final List<RoomBatonAuthorRow> rows;
  final List<BeaconParticipant> participants;
  final void Function(String? userId) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final showTiers = rows.map((r) => r.tier).toSet().length > 1;
    final byTier = <int, List<RoomBatonAuthorRow>>{};
    for (final r in rows) {
      if (r.candidate.response == RoomBatonResponse.canHelp) {
        byTier.putIfAbsent(r.tier, () => []).add(r);
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
            for (final r in byTier[tier]!)
              ListTile(
                leading: batonPersonAvatar(
                  userId: r.candidate.userId,
                  title: r.candidate.title,
                  participants: participants,
                ),
                title: Text(
                  r.partner == null
                      ? r.candidate.title
                      : l10n.batonPairNames(
                          r.candidate.title,
                          r.partner!.title,
                        ),
                ),
                subtitle: r.partner == null
                    ? null
                    : Text(l10n.batonChoosePairHint),
                onTap: () => onSelect(r.candidate.userId),
              ),
          ],
        ],
      ),
    );
  }
}
