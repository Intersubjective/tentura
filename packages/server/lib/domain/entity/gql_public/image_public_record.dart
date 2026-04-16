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
}
