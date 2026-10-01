import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Stroke of every example flow: all flows share one paint on purpose, so the
/// picture can never hint at how the author split anything (U20).
const _flowStroke = 3.0;

/// Example of how the author's pool reaches the colleagues: equal grey flows
/// labelled «пример». Takes only the roster size and the avatars — never a
/// share, percent or decision. [avatars] is the author first, then the members.
class ShareFlowDiagram extends StatelessWidget {
  const ShareFlowDiagram({
    required this.memberCount,
    required this.avatars,
    super.key,
  });

  final int memberCount;
  final List<Profile> avatars;

  @override
  Widget build(BuildContext context) {
    if (avatars.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final members = avatars.skip(1).toList();
    final flows = memberCount.clamp(0, members.length);
    final avatarSize = TenturaAvatar.resolveSize(
      context,
      TenturaAvatarSize.tiny,
    );
    final rowHeight = avatarSize + TenturaSpacing.row;
    final height = rowHeight * (members.isEmpty ? 1 : members.length);
    return ExcludeSemantics(
      child: Column(
        children: [
          Text(
            l10n.closureHelperDiagramExample,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          const SizedBox(height: TenturaSpacing.row),
          Row(
            children: [
              SizedBox(
                height: height,
                child: Center(
                  child: TenturaAvatar.tiny(profile: avatars.first),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: height,
                  child: CustomPaint(
                    painter: _FlowPainter(
                      flows: flows,
                      rowHeight: rowHeight,
                      // Neutral grey: the faint text token without its tint.
                      color: HSLColor.fromColor(
                        tt.textFaint,
                      ).withSaturation(0).toColor(),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  for (final m in members)
                    SizedBox(
                      height: rowHeight,
                      child: Center(child: TenturaAvatar.tiny(profile: m)),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One equal curve from the author's side (left, middle) to each of the first
/// [flows] member rows. Draws no text.
class _FlowPainter extends CustomPainter {
  const _FlowPainter({
    required this.flows,
    required this.rowHeight,
    required this.color,
  });

  final int flows;
  final double rowHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _flowStroke;
    final from = Offset(0, size.height / 2);
    for (var i = 0; i < flows; i++) {
      final to = Offset(size.width, rowHeight * (i + 0.5));
      final mid = size.width / 2;
      canvas.drawPath(
        Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(mid, from.dy, mid, to.dy, to.dx, to.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.flows != flows || old.rowHeight != rowHeight || old.color != color;
}
