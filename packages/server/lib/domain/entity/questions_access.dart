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

/// Why a person may only read Questions, or may not open it at all — so the
/// screen can say which of their own acts (or the Request's state) caused it
/// (#657). Told only to that person, about themselves.
enum QuestionsLimitReason {
  /// The Request is closed, cancelled or deleted: read-only for everyone.
  closed('closed'),

  /// They answered "Can't help" to the forward that brought it (Q4).
  cantHelp('cant_help'),

  /// They withdrew their help offer (Q7).
  withdrew('withdrew'),

  /// The author declined or removed their help offer.
  declined('declined'),

  /// The author removed them from Questions.
  removed('removed');

  const QuestionsLimitReason(this.wire);

  /// The GraphQL value (`readOnlyReason`).
  final String wire;
}

/// The raw facts behind [QuestionsLimitReason] for one person, read in one
/// query. They never grant access: the policy alone does
/// ([QuestionsAccess]).
final class QuestionsStandingFacts {
  const QuestionsStandingFacts({
    this.closed = false,
    this.banned = false,
    this.answeredCantHelp = false,
    this.pastOffer = false,
    this.offerWithdrawnByHelper = false,
  });

  /// Request status cancelled / deleted / closed.
  final bool closed;

  final bool banned;

  /// A live forward edge to them that they answered "Can't help".
  final bool answeredCantHelp;

  /// A help offer that is no longer live.
  final bool pastOffer;

  /// That past offer was withdrawn by the helper (a withdraw reason is set);
  /// otherwise the author declined or removed it.
  final bool offerWithdrawnByHelper;

  /// The reason for a person whose policy level is [access]; null when they
  /// write, or when nothing more specific than the level can be said.
  QuestionsLimitReason? reasonFor(
    QuestionsAccess access, {
    required bool lifecycleBlocksWrites,
  }) {
    switch (access) {
      case QuestionsAccess.write:
        return lifecycleBlocksWrites ? QuestionsLimitReason.closed : null;
      case QuestionsAccess.read:
        if (closed || lifecycleBlocksWrites) return QuestionsLimitReason.closed;
        if (pastOffer) {
          return offerWithdrawnByHelper
              ? QuestionsLimitReason.withdrew
              : QuestionsLimitReason.declined;
        }
        if (answeredCantHelp) return QuestionsLimitReason.cantHelp;
        return null;
      case QuestionsAccess.none:
        return banned ? QuestionsLimitReason.removed : null;
    }
  }
}
