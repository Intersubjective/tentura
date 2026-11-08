/// In-memory Post composer draft for VM/widget tests.
class PostCreateComposerDraftSnapshot {
  const PostCreateComposerDraftSnapshot({
    required this.body,
    this.draftId,
  });

  final String? draftId;
  final String body;
}

PostCreateComposerDraftSnapshot? _testSnapshot;

PostCreateComposerDraftSnapshot? readPostCreateComposerDraft() => _testSnapshot;

void writePostCreateComposerDraft({
  required String body,
  String? draftId,
}) {
  final trimmed = body.trim();
  if (trimmed.isEmpty && (draftId == null || draftId.isEmpty)) {
    _testSnapshot = null;
    return;
  }
  _testSnapshot = PostCreateComposerDraftSnapshot(
    draftId: draftId,
    body: body,
  );
}

void clearPostCreateComposerDraft() {
  _testSnapshot = null;
}

/// Clears the in-memory store between widget tests.
void resetPostCreateComposerDraftStoreForTest() {
  _testSnapshot = null;
}
