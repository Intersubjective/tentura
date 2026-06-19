import 'dart:math';
import 'dart:ui' as ui;

import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../tentura_icons.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Canonical avatar size buckets (responsive via [TenturaTokens] except [big]).
enum TenturaAvatarSize {
  big,
  medium,
  small,
  tiny,
}

/// MeritRank sector threshold for rating arcs (matches root `kRatingSector`).
const int kAvatarRatingSector = 100 ~/ 4;

/// Fixed diameter for [TenturaAvatarSize.big] (profile hero).
const double kTenturaAvatarBigSize = 160;

/// Default list-row avatar diameter ([TenturaAvatarSize.medium] on compact).
const double kTenturaAvatarDefaultMedium = kTenturaAvatarBigSize / 4;

/// Unified circular profile avatar: identifier, optional MeritRank chrome,
/// self halo, author star, and capability overlay badge.
class TenturaAvatar extends StatelessWidget {
  const TenturaAvatar({
    required this.profile,
    super.key,
    this.sizeBucket = TenturaAvatarSize.medium,
    this.size,
    this.showAuthorStar = false,
    this.isSelf = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : withContactBadge = withContactBadge ?? withRating;

  const TenturaAvatar.big({
    required this.profile,
    super.key,
    this.showAuthorStar = false,
    this.isSelf = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.big,
       size = kTenturaAvatarBigSize,
       withContactBadge = withContactBadge ?? withRating;

  const TenturaAvatar.medium({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.isSelf = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.medium,
       withContactBadge = withContactBadge ?? withRating;

  const TenturaAvatar.small({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.isSelf = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.small,
       withContactBadge = withContactBadge ?? withRating;

  const TenturaAvatar.tiny({
    required this.profile,
    super.key,
    this.size,
    this.showAuthorStar = false,
    this.isSelf = false,
    this.withRating = false,
    bool? withContactBadge,
    this.overlayBadge,
    this.boxFit = BoxFit.cover,
  }) : sizeBucket = TenturaAvatarSize.tiny,
       withContactBadge = withContactBadge ?? withRating;

  final Profile profile;
  final TenturaAvatarSize sizeBucket;
  final double? size;
  final bool showAuthorStar;
  final bool isSelf;
  final bool withRating;
  final bool withContactBadge;
  final Widget? overlayBadge;
  final BoxFit boxFit;

  static Widget avatarPlaceholder({
    int? cacheHeight,
    int? cacheWidth,
    BoxFit? fit,
  }) =>
      Image.asset(
        'images/placeholder/avatar.jpg',
        cacheHeight: cacheHeight,
        cacheWidth: cacheWidth,
        fit: fit,
      );

  static double resolveSize(BuildContext context, TenturaAvatarSize bucket) {
    final tt = context.tt;
    return switch (bucket) {
      TenturaAvatarSize.big => kTenturaAvatarBigSize,
      TenturaAvatarSize.medium => tt.avatarSize,
      TenturaAvatarSize.small => tt.metadataAvatarSize,
      TenturaAvatarSize.tiny => tt.avatarTinySize,
    };
  }

  double _effectiveSize(BuildContext context) =>
      size ?? resolveSize(context, sizeBucket);

  bool _allowsMeritDecorations(BuildContext context, double s) {
    return switch (sizeBucket) {
      TenturaAvatarSize.tiny => s >= context.tt.metadataAvatarSize,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final s = _effectiveSize(context);
    final cache = s.ceil();
    final meritOk = _allowsMeritDecorations(context, s);
    final paintRating = withRating && meritOk;
    final paintContact = withContactBadge && meritOk;

    final initials = initialsForProfile(profile);
    final avatarCore = profile.hasNoAvatar
        ? ProfileAvatarInitials(lettering: initials, size: s)
        : _Network(
            profile: profile,
            cacheSize: cache,
            initials: initials,
            size: s,
            boxFit: boxFit,
          );

    Widget inner = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tt.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarCore,
    );

    if (paintRating || paintContact) {
      final scheme = Theme.of(context).colorScheme;
      inner = SizedBox.square(
        dimension: s,
        child: CustomPaint(
          painter: paintRating
              ? _RatingArcsPainter(
                  color: scheme.primary,
                  score: profile.score,
                )
              : null,
          foregroundPainter: paintContact
              ? _AvatarBadgePainter(
                  color: scheme.primary,
                  badgeFill: scheme.surface,
                  isSeeingMe: profile.isSeeingMe,
                  isMutualFriend: profile.isMutualFriend,
                )
              : null,
          child: paintRating
              ? Padding(
                  padding: EdgeInsets.all(s / 8),
                  child: inner,
                )
              : inner,
        ),
      );
    } else {
      inner = SizedBox.square(dimension: s, child: inner);
    }

    if (isSelf) {
      inner = _SelfHalo(size: s, child: inner);
    }

    if (showAuthorStar || overlayBadge != null) {
      inner = Stack(
        clipBehavior: Clip.none,
        children: [
          inner,
          if (showAuthorStar) ProfileAuthorStarBadge(avatarSize: s),
          if (overlayBadge != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: _OverlayBadge(size: s, child: overlayBadge!),
            ),
        ],
      );
    }

    return inner;
  }

  /// Initials when there is no profile photo (also used by room mini avatars).
  static String initialsForProfile(Profile profile) {
    final t = profile.displayName.trim();
    if (t.isEmpty) {
      return '?';
    }
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final a = parts[0].isNotEmpty ? parts[0][0] : '';
      final b = parts[1].isNotEmpty ? parts[1][0] : '';
      return '$a$b'.toUpperCase();
    }
    if (t.length >= 2) {
      return t.substring(0, 2).toUpperCase();
    }
    return t[0].toUpperCase();
  }
}

class _Network extends StatelessWidget {
  const _Network({
    required this.profile,
    required this.cacheSize,
    required this.initials,
    required this.size,
    required this.boxFit,
  });

  final Profile profile;
  final int cacheSize;
  final String initials;
  final double size;
  final BoxFit boxFit;

  @override
  Widget build(BuildContext context) {
    final image = profile.image;
    final net = Image.network(
      profile.avatarUrl,
      errorBuilder: (context, error, stackTrace) =>
          ProfileAvatarInitials(lettering: initials, size: size),
      cacheHeight: cacheSize,
      cacheWidth: cacheSize,
      fit: boxFit,
    );
    if (image?.blurHash.isEmpty ?? true) {
      return net;
    }
    return BlurHash(
      image!.blurHash,
      child: net,
    );
  }
}

/// Circular initials fallback when a profile has no photo (or network load fails).
class ProfileAvatarInitials extends StatelessWidget {
  const ProfileAvatarInitials({
    required this.lettering,
    required this.size,
    super.key,
  });

  final String lettering;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final fontSize = size * 0.38;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          lettering,
          maxLines: 1,
          style: TenturaText.bodySmall(tt.textFaint).copyWith(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Bottom-right star badge for beacon author avatars (HUD, stacks, tiles).
class ProfileAuthorStarBadge extends StatelessWidget {
  const ProfileAuthorStarBadge({
    required this.avatarSize,
    super.key,
  });

  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final iconSize = avatarSize * 0.5;
    return Positioned(
      right: -2,
      bottom: -2,
      child: Icon(
        Icons.star_rounded,
        size: iconSize,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _SelfHalo extends StatelessWidget {
  const _SelfHalo({
    required this.size,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          IgnorePointer(
            child: CustomPaint(
              painter: _SelfAvatarRingPainter(
                color: color,
                strokeWidth: 2,
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

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({
    required this.size,
    required this.child,
  });

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeSize = size * 0.44;
    final iconSize = size * 0.26;
    return Container(
      width: badgeSize,
      height: badgeSize,
      decoration: BoxDecoration(
        color: scheme.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: scheme.outlineVariant,
        ),
      ),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: IconTheme.merge(
          data: IconThemeData(size: iconSize),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: child,
          ),
        ),
      ),
    );
  }
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
      if (score > kAvatarRatingSector * (i + 1)) {
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

/// Bottom-right MeritRank eye or mutual-contact badge.
class _AvatarBadgePainter extends CustomPainter {
  _AvatarBadgePainter({
    required this.color,
    required this.badgeFill,
    required this.isSeeingMe,
    required this.isMutualFriend,
  });

  final Color color;
  final Color badgeFill;
  final bool? isSeeingMe;
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
