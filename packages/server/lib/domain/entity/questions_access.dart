/// What a person may do in a Request's **Questions** space (internally: the
/// Request lobby, U088). Computed only by the server-owned policy
/// `public.questions_access_levels` (m0254); see
/// `docs/features/beacon_questions.md`.
enum QuestionsAccess {
  /// Not in the addressed audience, banned, blocked, or the Request content
  /// is not readable.
  none,

  /// Reads the whole thread, cannot post: answered "Can't help", withdrew or
  /// was declined, or the Request is closed.
  read,

  /// Reads and posts.
  write;

  /// The policy's wire level: 0 none, 1 read, 2 write.
  static QuestionsAccess fromLevel(int level) => switch (level) {
    2 => write,
    1 => read,
    _ => none,
  };

  bool get canRead => this != none;

  bool get canWrite => this == write;
}

/// One audience member of a Request's Questions space.
final class QuestionsAudienceMember {
  const QuestionsAudienceMember({
    required this.userId,
    required this.displayName,
    required this.handle,
    required this.access,
  });

  final String userId;
  final String displayName;
  final String handle;
  final QuestionsAccess access;
}

/// Someone the author removed from Questions.
final class QuestionsBannedUser {
  const QuestionsBannedUser({required this.userId, required this.displayName});

  final String userId;
  final String displayName;
}
