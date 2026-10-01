import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The author's closure story (system message `closureStory`) as a centered
/// system card: placed the same whoever wrote it, no sender header.
class RoomClosureStoryCard extends StatelessWidget {
  const RoomClosureStoryCard({required this.message, super.key});

  final RoomMessage message;

  static bool isClosureStoryRow(RoomMessage m) =>
      m.systemMessageKind == BeaconRoomSystemMessageKind.closureStory;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.tightGap,
      ),
      child: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(TenturaSpacing.cardPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.closureStoryRoomTitle,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: TenturaSpacing.row),
                Text(message.body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
