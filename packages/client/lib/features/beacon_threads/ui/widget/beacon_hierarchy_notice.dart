import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Renders a hierarchy creation/lifecycle notice using the same centered,
/// person-free chrome as the existing participant-admission notice
/// (plan §6.2). An unknown/unparseable payload renders generic,
/// non-actionable system-event text rather than failing to build.
class BeaconHierarchyNotice extends StatelessWidget {
  const BeaconHierarchyNotice({required this.message, super.key});

  final RoomMessage message;

  /// Whether [message] should be rendered by this widget instead of an
  /// ordinary chat bubble.
  static bool isHierarchyNoticeRow(RoomMessage m) =>
      m.systemMessageKind == BeaconRoomSystemMessageKind.hierarchyLifecycle ||
      m.systemMessageKind == BeaconRoomSystemMessageKind.childCreated;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt =
        theme.extension<TenturaTokens>() ??
        (theme.brightness == Brightness.dark
            ? TenturaTokens.dark
            : TenturaTokens.light);

    final payload = message.hierarchyPayload;
    final line = switch (payload) {
      RoomMessageHierarchyChildCreated() => l10n.beaconHierarchyNoticeChildCreated,
      RoomMessageHierarchyLifecycle() => message.body,
      null => l10n.beaconHierarchyNoticeUnknown,
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.tightGap / 2,
        tt.screenHPadding,
        tt.tightGap / 2,
      ),
      child: Semantics(
        label: line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            SizedBox(width: tt.iconTextGap / 2),
            Flexible(
              child: Text(
                line,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
