Set<String> uncoveredRecipientIds({
  required Set<String> selectedIds,
  required Map<String, String> perRecipientNotes,
  required Set<String> skippedPersonalNoteIds,
}) {
  return selectedIds
      .where(
        (id) =>
            !skippedPersonalNoteIds.contains(id) &&
            (perRecipientNotes[id]?.trim().isEmpty ?? true),
      )
      .toSet();
}

String? effectiveForwardNote({String? personal, String? shared}) {
  final trimmedPersonal = personal?.trim();
  if (trimmedPersonal != null && trimmedPersonal.isNotEmpty) {
    return trimmedPersonal;
  }
  final trimmedShared = shared?.trim();
  if (trimmedShared != null && trimmedShared.isNotEmpty) {
    return trimmedShared;
  }
  return null;
}

bool forwardEdgeIsCancellable({
  required DateTime? recipientReadAt,
  required bool hasOnwardChild,
  required bool recipientHasActiveHelpOffer,
  required bool recipientDeclined,
}) {
  return recipientReadAt == null &&
      !hasOnwardChild &&
      !recipientHasActiveHelpOffer &&
      !recipientDeclined;
}
