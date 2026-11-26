import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/repository/private_avatar_repository.dart';

/// An owner's Field photo, with the surface's usual avatar as its fallback.
class PrivatePersonAvatar extends StatelessWidget {
  const PrivatePersonAvatar({
    required this.objectKey,
    required this.size,
    required this.fallback,
    super.key,
  });

  final String? objectKey;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final key = objectKey;
    if (key == null) return fallback;
    return _PrivatePhoto(
      key: ValueKey(key),
      objectKey: key,
      size: size,
      fallback: fallback,
    );
  }
}

class _PrivatePhoto extends StatefulWidget {
  const _PrivatePhoto({
    required this.objectKey,
    required this.size,
    required this.fallback,
    super.key,
  });

  final String objectKey;
  final double size;
  final Widget fallback;

  @override
  State<_PrivatePhoto> createState() => _PrivatePhotoState();
}

class _PrivatePhotoState extends State<_PrivatePhoto> {
  late final _bytes = const PrivateAvatarRepository().read(widget.objectKey);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (bytes == null) return widget.fallback;
      return ClipOval(
        child: Image.memory(
          bytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          cacheWidth: widget.size.ceil(),
          errorBuilder: (_, _, _) => widget.fallback,
        ),
      );
    },
  );
}
