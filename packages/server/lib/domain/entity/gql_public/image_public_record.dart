import 'package:meta/meta.dart';

/// Public image fields aligned with Hasura / `gqlTypeImagePublic`.
@immutable
class ImagePublicRecord {
  const ImagePublicRecord({
    required this.id,
    required this.hash,
    required this.height,
    required this.width,
    required this.authorId,
    required this.createdAt,
  });

  final String id;
  final String hash;
  final int height;
  final int width;
  final String authorId;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagePublicRecord &&
          other.id == id &&
          other.hash == hash &&
          other.height == height &&
          other.width == width &&
          other.authorId == authorId &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, hash, height, width, authorId, createdAt);
}
