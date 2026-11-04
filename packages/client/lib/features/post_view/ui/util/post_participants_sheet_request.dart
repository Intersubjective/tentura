/// One-shot flag: open «О посте» scrolled to participants after navigation.
final class PostParticipantsSheetRequest {
  PostParticipantsSheetRequest._();

  static final instance = PostParticipantsSheetRequest._();

  String? _postId;

  set pending(String postId) => _postId = postId;

  String? get pending => _postId;

  bool takeFor(String postId) {
    if (_postId != postId) return false;
    _postId = null;
    return true;
  }
}
