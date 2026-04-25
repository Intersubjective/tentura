import 'package:flutter/material.dart';

import 'package:tentura/features/my_work/ui/widget/my_work_status_line.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

/// Single-line operational status for My Desk cards: `slot1 · slot2 · slot3`.
///
/// [MyWorkStatusLineData.slot3] is the rightmost segment and ellipsizes first
/// under tight width ([Expanded]).
class MyWorkCardStatusStrip extends StatelessWidget {
  const MyWorkCardStatusStrip({
    required this.data,
    super.key,
  });

  final MyWorkStatusLineData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final baseStyle = beaconCardStatusLineTextStyle(theme);
    final slot2Style = data.timeSlotOverdue
        ? baseStyle.copyWith(
            color: scheme.error,
            fontWeight: FontWeight.w600,
          )
        : baseStyle;

    return Padding(
      padding: EdgeInsets.zero,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: data.slot1, style: baseStyle),
            TextSpan(text: ' · ', style: baseStyle),
            TextSpan(text: data.slot2, style: slot2Style),
            TextSpan(text: ' · ', style: baseStyle),
            TextSpan(text: data.slot3, style: baseStyle),
          ],
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
