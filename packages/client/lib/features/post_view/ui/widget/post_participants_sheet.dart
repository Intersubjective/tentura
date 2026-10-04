import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Sheet listing the people who are in the Post's conversation.
Future<void> showPostParticipantsSheet(
  BuildContext context, {
  required List<BeaconParticipant> participants,
}) {
  final members = participants
      .where((p) => p.roomAccess == RoomAccessBits.admitted)
      .toList();
  return showTenturaAdaptiveSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext)!;
      final tt = sheetContext.tt;
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.rowGap,
                ),
                child: Text(
                  l10n.postParticipantsTitle(members.length),
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const Divider(height: 1),
              for (final member in members)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tt.screenHPadding,
                    vertical: tt.rowGap,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          member.displayLabel(l10n.unknownPerson),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (member.role == BeaconParticipantRoleBits.author)
                        Text(
                          l10n.postParticipantAuthor,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
