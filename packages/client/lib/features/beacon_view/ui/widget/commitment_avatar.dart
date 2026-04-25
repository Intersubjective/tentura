import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
/// 32×32 rounded-square avatar (radius 8) for the Commitments tab — not social/round.
class CommitmentAvatar extends StatelessWidget {
  const CommitmentAvatar({
    required this.profile,
    super.key,
  });

  static const double size = 32;
  static const double cornerRadius = 8;

  final Profile profile;

  int get _cacheSize => size.ceil();

  String get _initials {
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = profile.hasNoAvatar
        ? _Initials(lettering: _initials, scheme: scheme)
        : _NetworkOrBlur(
            profile: profile,
            cacheSize: _cacheSize,
            initials: _initials,
            scheme: scheme,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: base,
      ),
    );
  }
}

class _NetworkOrBlur extends StatelessWidget {
  const _NetworkOrBlur({
    required this.profile,
    required this.cacheSize,
    required this.initials,
    required this.scheme,
  });

  final Profile profile;
  final int cacheSize;
  final String initials;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final image = profile.image;
    final net = Image.network(
      profile.avatarUrl,
      errorBuilder: (_, _, _) => _Initials(lettering: initials, scheme: scheme),
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
    required this.scheme,
  });

  final String lettering;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          lettering,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}
