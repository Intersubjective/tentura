/// Sanitizes a raw build id (commit SHA, branch ref, etc.) for display and
/// cache-busting version strings.
String sanitizeBuildId(String raw, {int maxLength = 12}) {
  final safeId = raw.replaceAll(RegExp('[^A-Za-z0-9]'), '');
  if (safeId.isEmpty) return '';
  return safeId.length > maxLength ? safeId.substring(0, maxLength) : safeId;
}
