import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../tentura_tokens.dart';
import '../tentura_text.dart';

/// 32px circular identifier avatar; thin border; initials fallback 10 semibold.
class TenturaAvatar extends StatelessWidget {
  const TenturaAvatar({
    required this.profile,
    super.key,
    this.size,
  });

  final Profile profile;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final s = size ?? tt.avatarSize;
    final cache = s.ceil();
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tt.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: profile.hasNoAvatar
          ? _Initials(lettering: _initialsFor(profile), size: s)
          : _Network(
              profile: profile,
              cacheSize: cache,
              initials: _initialsFor(profile),
              size: s,
            ),
    );
  }

  static String _initialsFor(Profile profile) {
    final t = profile.title.trim();
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
  });

  final Profile profile;
  final int cacheSize;
  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = profile.image;
    final net = Image.network(
      profile.avatarUrl,
      errorBuilder: (context, error, stackTrace) =>
          _Initials(lettering: initials, size: size),
      cacheHeight: cacheSize,
      cacheWidth: cacheSize,
      fit: BoxFit.cover,
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

class _Initials extends StatelessWidget {
  const _Initials({
    required this.lettering,
    required this.size,
  });

  final String lettering;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          lettering,
          maxLines: 1,
          style: TenturaText.bodySmall(tt.textFaint).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
