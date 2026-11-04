import 'package:flutter/foundation.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

/// One admitted peer shown in a Post conversations row avatar stack.
@immutable
final class PostParticipantPreview {
  const PostParticipantPreview({
    required this.id,
    required this.displayName,
    this.avatar = '',
  });

  final String id;
  final String displayName;

  /// Full avatar URL from the MyPosts previewParticipants GraphQL field.
  final String avatar;

  Profile toProfile() {
    final url = avatar.trim();
    if (url.isEmpty || url == kAvatarPlaceholderUrl) {
      return Profile(id: id, displayName: displayName);
    }
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? const [];
    if (segments.length >= 2) {
      final file = segments.last;
      final dot = file.lastIndexOf('.');
      final imageId = dot > 0 ? file.substring(0, dot) : file;
      if (imageId.isNotEmpty) {
        return Profile(
          id: id,
          displayName: displayName,
          image: ImageEntity(id: imageId, authorId: id),
        );
      }
    }
    return Profile(id: id, displayName: displayName);
  }
}
