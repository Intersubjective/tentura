String notificationExcerpt(String text, {int maxChars = 80}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.length <= maxChars) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxChars - 1)}…';
}
