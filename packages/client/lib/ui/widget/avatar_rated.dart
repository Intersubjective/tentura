import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:blurhash_shader/blurhash_shader.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'tentura_icons.dart';

class AvatarRated extends StatelessWidget {
  static const sizeBig = 160.0;

  static const sizeSmall = sizeBig / 4;

  // TBD: remove assets
  static Widget getAvatarPlaceholder({
    int? cacheHeight,
    int? cacheWidth,
    BoxFit? fit,
  }) => Image.asset(
    'images/placeholder/avatar.jpg',
    cacheHeight: cacheHeight,
    cacheWidth: cacheWidth,
    fit: fit,
  );

  AvatarRated({
    required this.profile,
    this.withRating = true,
    this.boxFit = BoxFit.cover,
    this.size = sizeSmall,
    super.key,
  });

  AvatarRated.big({
    required this.profile,
    this.withRating = true,
    super.key,
  }) : boxFit = BoxFit.cover,
       size = sizeBig;

  AvatarRated.small({
    required this.profile,
    this.withRating = true,
    super.key,
  }) : boxFit = BoxFit.cover,
       size = sizeSmall;

  final double size;

  final BoxFit boxFit;

  final Profile profile;

  final bool withRating;

  late final _cacheSize = size.ceil();

  late final _avatar = ClipOval(
    child: profile.hasNoAvatar
        ? getAvatarPlaceholder(
            cacheHeight: _cacheSize,
            cacheWidth: _cacheSize,
            fit: boxFit,
          )
        : profile.image?.blurHash.isEmpty ?? true
        ? _imageNetwork
        : BlurHash(
            profile.image!.blurHash,
            child: _imageNetwork,
          ),
  );

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: withRating
        ? CustomPaint(
            painter: _RatingArcsPainter(
              color: Theme.of(context).colorScheme.primary,
              score: profile.score,
            ),
            foregroundPainter: _AvatarBadgePainter(
              color: Theme.of(context).colorScheme.primary,
              badgeFill: Theme.of(context).colorScheme.surface,
              isSeeingMe: profile.isSeeingMe,
              isMutualFriend: profile.isMutualFriend,
            ),
            child: Padding(
              padding: EdgeInsets.all(size / 8),
              child: _avatar,
            ),
          )
        : _avatar,
  );

  Widget get _imageNetwork => Image.network(
    profile.avatarUrl,
    errorBuilder: (_, _, _) => getAvatarPlaceholder(
      cacheHeight: _cacheSize,
      cacheWidth: _cacheSize,
      fit: boxFit,
    ),
    cacheHeight: _cacheSize,
    cacheWidth: _cacheSize,
    fit: boxFit,
  );
}

class _RatingArcsPainter extends CustomPainter {
  _RatingArcsPainter({
    required this.color,
    required this.score,
  });

  final Color color;

  final double score;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeWidth = size.height / 12
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < 3; i++) {
      if (score > kRatingSector * (i + 1)) {
        canvas.drawArc(
          rect,
          _degreeToRadians(90 + 67.5 * i),
          _degreeToRadians(45),
          false,
          paint,
        );
      } else {
        break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RatingArcsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.score != score;

  static double _degreeToRadians(double degree) => (pi / 180) * degree;
}

/// Bottom-right MeritRank eye or mutual-contact badge — painted above the avatar
/// ([CustomPaint.foregroundPainter]) so overlays are not clipped under the oval.
class _AvatarBadgePainter extends CustomPainter {
  _AvatarBadgePainter({
    required this.color,
    required this.badgeFill,
    required this.isSeeingMe,
    required this.isMutualFriend,
  });

  final Color color;

  /// Filled disc behind mutual-contact link (matches SVG `--badge-bg`; theme surface).
  final Color badgeFill;

  final bool? isSeeingMe;

  /// Reciprocal positive `vote_user` with viewer; replaces eye when true.
  final bool isMutualFriend;

  @override
  void paint(Canvas canvas, Size size) {
    if (isMutualFriend) {
      _paintMutualContactBadge(canvas, size, color, badgeFill);
    } else {
      final eye = _eyeGlyph(isSeeingMe);
      if (eye != null) {
        _paintBottomRightIconGlyph(canvas, size, color, eye);
      }
    }
  }

  /// Same geometry as `images/mutual_contact_badge.svg` (viewBox 0 0 24 24).
  /// Horizontally right-aligned like [_paintBottomRightIconGlyph] (paragraph width + right align).
  static void _paintMutualContactBadge(
    Canvas canvas,
    Size box,
    Color primary,
    Color discFill,
  ) {
    final slotLeft = box.height / 8;
    final slotTop = box.width / 1.5;
    final scale = box.height / 2 / 24;
    final iconSize = 24 * scale;

    final disc = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = discFill;

    final ring = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primary.withValues(alpha: 0.16);

    final link = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = primary;
    final bar = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 10.9, 10, 2.2),
      const Radius.circular(1.1),
    );

    canvas
      ..save()
      ..translate(slotLeft + box.width - iconSize, slotTop)
      ..scale(scale)
      ..drawCircle(const Offset(12, 12), 10, disc)
      ..drawCircle(const Offset(12, 12), 9.25, ring)
      ..drawRRect(bar, link)
      ..drawCircle(const Offset(7, 12), 3, link)
      ..drawCircle(const Offset(17, 12), 3, link)
      ..restore();
  }

  /// Same layout path as the original eye overlay so glyphs share one position.
  static void _paintBottomRightIconGlyph(
    Canvas canvas,
    Size box,
    Color color,
    IconData icon,
  ) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontFamily: icon.fontFamily,
        textAlign: TextAlign.right,
        fontSize: box.height / 2,
        maxLines: 1,
      ),
    )
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(String.fromCharCode(icon.codePoint));
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: box.width));
    canvas.drawParagraph(
      paragraph,
      Offset(box.height / 8, box.width / 1.5),
    );
  }

  static IconData? _eyeGlyph(bool? isSeeingMe) {
    if (isSeeingMe == null) {
      return null;
    }
    return isSeeingMe ? TenturaIcons.eyeOpen : TenturaIcons.eyeClosed;
  }

  @override
  bool shouldRepaint(covariant _AvatarBadgePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.badgeFill != badgeFill ||
      oldDelegate.isSeeingMe != isSeeingMe ||
      oldDelegate.isMutualFriend != isMutualFriend;
}
