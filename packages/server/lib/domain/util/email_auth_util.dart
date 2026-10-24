/// Normalizes an email for credential lookup and transactions.
String normalizeAuthEmail(String raw) => raw.trim().toLowerCase();

/// Display name of a new email account until the person picks one. Never
/// derived from the email: that leaked the local-part to everyone (#660).
/// The landing and the app treat this exact name as "no name chosen yet".
const kNewMemberDisplayName = 'New member';

final RegExp kAuthEmailPattern = RegExp(
  r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$',
);

bool isValidAuthEmailFormat(String normalized) =>
    normalized.isNotEmpty && kAuthEmailPattern.hasMatch(normalized);
