import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/normalize.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../bloc/rating_cubit.dart';

class RatingListTile extends StatelessWidget {
  RatingListTile({
    required this.profile,
    required this.isDarkMode,
    this.height = 40,
    this.ratio = 2.5,
    super.key,
  });

  final bool isDarkMode;
  final double ratio;
  final double height;
  final Profile profile;

  late final _barbellSize = Size(height * ratio, height);

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () => context.read<RatingCubit>().showProfile(profile.id),
    child: Row(
      children: [
        AvatarRated(
          profile: profile,
          size: height,
        ),
        Expanded(
          child: Padding(
            padding: kPaddingH,
            child: Text(
              profile.title,
              maxLines: 2,
            ),
          ),
        ),
        CustomPaint(
          size: _barbellSize,
          painter: _CustomBarbellPainter(
            profile.score,
            profile.rScore,
            isDarkMode,
          ),
        ),
      ],
    ),
  );
}

class _CustomBarbellPainter extends CustomPainter {
  const _CustomBarbellPainter(
    this.leftWeight,
    this.rightWeight,
    this.isDarkTheme,
  );

  final bool isDarkTheme;
  final double leftWeight;
  final double rightWeight;

  @override
  void paint(Canvas canvas, Size size) {
    final halfHeight = size.height / 2;
    final leftOffset = Offset(halfHeight, halfHeight);
    final rightOffset = Offset(size.width - halfHeight, halfHeight);
    final maxRadius = halfHeight;
    final minRadius = halfHeight / 4;
    final leftColor = calculateColor(
      weight: leftWeight,
      isDark: isDarkTheme,
    );
    final rightColor = calculateColor(
      weight: rightWeight,
      isDark: isDarkTheme,
    );
    canvas
      ..drawLine(
        leftOffset,
        rightOffset,
        Paint()
          ..strokeWidth = halfHeight / 4
          ..shader = LinearGradient(
            colors: [leftColor, rightColor],
          ).createShader(Rect.fromPoints(leftOffset, rightOffset)),
      )
      ..drawCircle(
        leftOffset,
        calculateRadius(
          minRadius: minRadius,
          maxRadius: maxRadius,
          weight: leftWeight,
        ),
        Paint()..color = leftColor,
      )
      ..drawCircle(
        rightOffset,
        calculateRadius(
          minRadius: minRadius,
          maxRadius: maxRadius,
          weight: rightWeight,
        ),
        Paint()..color = rightColor,
      );
  }

  @override
  bool shouldRepaint(_CustomBarbellPainter oldDelegate) => false;

  @override
  bool shouldRebuildSemantics(_CustomBarbellPainter oldDelegate) => false;
}
