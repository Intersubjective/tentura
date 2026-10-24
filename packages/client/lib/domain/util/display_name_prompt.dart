/// Display name the server gives a new email account until the person picks
/// one (server `kNewMemberDisplayName`, #660).
const kNewMemberDisplayName = 'New member';

/// What [kNewMemberDisplayName] reads as in the app language. The server
/// stores the English constant; the app sets the localized label whenever its
/// locale changes ([setNewMemberDisplayNameLabel]).
String _newMemberDisplayNameLabel = kNewMemberDisplayName;

/// Called by the app with `L10n.newMemberDisplayName` for the current locale.
void setNewMemberDisplayNameLabel(String label) =>
    _newMemberDisplayNameLabel = label;

/// [displayName] as shown to people: the server placeholder
/// [kNewMemberDisplayName] in the app language, any other name unchanged.
String localizedDisplayName(String displayName) =>
    displayName.trim() == kNewMemberDisplayName
    ? _newMemberDisplayNameLabel
    : displayName;

/// Heuristic for whether the user still has a server placeholder name
/// ("New member", or an older email local-part) rather than a chosen one.
bool needsDisplayNamePromptFor(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty || trimmed == kNewMemberDisplayName) return true;
  if (trimmed != trimmed.toLowerCase()) return false;
  return RegExp(r'\d').hasMatch(trimmed);
}
