import 'package:tentura_server/domain/entity/user_contact_entity.dart';

abstract class UserContactRepositoryPort {
  /// Creates or replaces the viewer's contact name for the subject.
  Future<void> upsert({
    required String viewerId,
    required String subjectId,
    required String contactName,
  });

  /// Removes the contact entry; returns false when none existed.
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  });

  /// All contact entries of [viewerId] (the client syncs this full map).
  Future<List<UserContactEntity>> fetchAllByViewer({
    required String viewerId,
  });

  /// The viewer's name for [subjectId], or null when no entry exists.
  Future<String?> getName({
    required String viewerId,
    required String subjectId,
  });
}
