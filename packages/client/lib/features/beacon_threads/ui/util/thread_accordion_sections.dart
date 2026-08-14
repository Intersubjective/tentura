/// Stable accordion section ids for the Threads tab.
abstract final class ThreadAccordionSection {
  static const active = 'active';
  static const closed = 'closed';
  static const drafts = 'drafts';
}

/// Which Threads fold should be open on compact (focus-aware).
String? threadsTabAccordionSectionId({
  required bool focusInDrafts,
  required bool focusInClosed,
  required bool showActiveFold,
  required bool showClosedFold,
  required bool showDrafts,
}) {
  if (focusInDrafts && showDrafts) {
    return ThreadAccordionSection.drafts;
  }
  if (focusInClosed && showClosedFold) {
    return ThreadAccordionSection.closed;
  }
  if (showActiveFold) {
    return ThreadAccordionSection.active;
  }
  if (showClosedFold) {
    return ThreadAccordionSection.closed;
  }
  if (showDrafts) {
    return ThreadAccordionSection.drafts;
  }
  return null;
}
