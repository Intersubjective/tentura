import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';

/// Single-line operational status for My Desk cards: `slot1 · slot2 · slot3`.
///
/// [MyWorkStatusLineData.slot3] is the rightmost segment and ellipsizes first
/// under tight width ([Expanded]).
class MyWorkCardStatusStrip extends StatelessWidget {
  const MyWorkCardStatusStrip({
    required this.data,
    this.roomSubtitle,
    super.key,
  });

  final MyWorkStatusLineData data;

  /// Optional second line (room coordination / unread).
  final String? roomSubtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final baseStyle = TenturaText.status(tt.textMuted).copyWith(
      fontWeight: FontWeight.w500,
    );
    final response = data.slot1ResponseType;
    final coord = data.slot1CoordinationStatus;
    final slot1Color = response != null
        ? coordinationResponseOnSurfaceColor(scheme, response)
        : (coord != null
            ? coordinationStatusOnSurfaceColor(scheme, coord)
            : null);
    final slot1Style = slot1Color != null
        ? baseStyle.copyWith(
            color: slot1Color,
            fontWeight: FontWeight.w600,
          )
        : baseStyle;
    final slot2Style = data.timeSlotOverdue
        ? baseStyle.copyWith(
            color: scheme.error,
            fontWeight: FontWeight.w600,
          )
        : baseStyle;

    final line = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: data.slot1, style: slot1Style),
          TextSpan(text: ' · ', style: baseStyle),
          TextSpan(text: data.slot2, style: slot2Style),
          TextSpan(text: ' · ', style: baseStyle),
          TextSpan(text: data.slot3, style: baseStyle),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );

    final room = roomSubtitle?.trim();
    if (room == null || room.isEmpty) {
      return Padding(padding: EdgeInsets.zero, child: line);
    }
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          Padding(
            padding: EdgeInsets.only(top: tt.iconTextGap / 2),
            child: Text(
              room,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
