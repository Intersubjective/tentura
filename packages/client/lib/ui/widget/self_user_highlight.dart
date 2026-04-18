import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Visual treatment when a [Profile] is the signed-in viewer.
abstract final class SelfUserHighlight {
  SelfUserHighlight._();

  static bool profileIsSelf(Profile profile, String viewerUserId) =>
      profile.id.isNotEmpty &&
      viewerUserId.isNotEmpty &&
      profile.id == viewerUserId;

  /// Accent label for the current user (distinct from [L10n.labelMe]).
  static String displayName(L10n l10n, Profile profile, String viewerUserId) =>
      profileIsSelf(profile, viewerUserId) ? l10n.labelYou : profile.title;

  static TextStyle selfNameStyle(ThemeData theme) {
    final scheme = theme.colorScheme;
    return TextStyle(
      // Same accent as [wrapSmallAvatar] ring (tertiary defaults are off-theme).
      color: scheme.primary,
      fontWeight: FontWeight.w600,
    );
  }

  /// Merges [base] with [selfNameStyle] when [isSelf].
  static TextStyle nameStyle(
    ThemeData theme,
    TextStyle? base,
    bool isSelf,
  ) {
    if (!isSelf) {
      return base ?? const TextStyle();
    }
    return (base ?? theme.textTheme.bodyMedium!).merge(selfNameStyle(theme));
  }

  /// Primary ring on top of [child]; total layout size matches the child bounds.
  static Widget wrapSmallAvatar(
    BuildContext context, {
    required Widget child,
    required double avatarSize,
    required bool isSelf,
  }) {
    if (!isSelf) {
      return child;
    }
    final color = Theme.of(context).colorScheme.primary;
    const strokeWidth = 2.0;
    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          IgnorePointer(
            child: CustomPaint(
              painter: _SelfAvatarRingPainter(
                color: color,
                strokeWidth: strokeWidth,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelfAvatarRingPainter extends CustomPainter {
  _SelfAvatarRingPainter({
    required this.color,
    required this.strokeWidth,
  });

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _SelfAvatarRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
