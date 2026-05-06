/// Extracts `@handle` tokens from message [body] (handles are 5–30 `[a-z0-9_]`,
/// case-insensitive; returned tokens are lowercased for resolution).
List<String> extractMentionHandleTokens(String body) {
  final re = RegExp('@([a-zA-Z0-9_]{5,30})');
  final seen = <String>{};
  final out = <String>[];
  for (final m in re.allMatches(body)) {
    final raw = m.group(1);
    if (raw == null) {
      continue;
    }
    final lower = raw.toLowerCase();
    if (!seen.add(lower)) {
      continue;
    }
    out.add(lower);
  }
  return out;
}
