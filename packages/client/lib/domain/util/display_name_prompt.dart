/// Heuristic for whether the user still has a server-derived placeholder name
/// (email local-part) rather than a chosen display name.
bool needsDisplayNamePromptFor(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed != trimmed.toLowerCase()) return false;
  return RegExp(r'\d').hasMatch(trimmed);
}
