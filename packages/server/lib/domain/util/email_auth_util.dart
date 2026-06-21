/// Normalizes an email for credential lookup and transactions.
String normalizeAuthEmail(String raw) => raw.trim().toLowerCase();

/// Derives a display name from the email local-part (new invited accounts).
String displayNameFromEmail(String normalizedEmail) {
  final at = normalizedEmail.indexOf('@');
  final local = at > 0 ? normalizedEmail.substring(0, at) : normalizedEmail;
  final cleaned = local
      .replaceAll(RegExp('[._+-]+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'User';
  if (cleaned.length <= 50) return cleaned;
  return cleaned.substring(0, 50);
}

final RegExp kAuthEmailPattern = RegExp(
  r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$',
);

bool isValidAuthEmailFormat(String normalized) =>
    normalized.isNotEmpty && kAuthEmailPattern.hasMatch(normalized);
