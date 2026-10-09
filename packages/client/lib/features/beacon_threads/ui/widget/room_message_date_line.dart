import 'package:flutter/material.dart';

/// Time line of an edited message: the send [time], then the edited
/// [suffix] carrying the edit time as a [tooltip] (hover on desktop,
/// long-press on touch; also its semantics label for assistive tech).
class RoomMessageEditedDateLine extends StatelessWidget {
  const RoomMessageEditedDateLine({
    required this.time,
    required this.suffix,
    required this.tooltip,
    required this.style,
    super.key,
  });

  final String time;
  final String suffix;
  final String tooltip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Text('$time · ', style: style),
      Tooltip(
        message: tooltip,
        child: Text(suffix, style: style),
      ),
    ],
  );
}
