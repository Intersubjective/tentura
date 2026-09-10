/// Formats the Receipts primary-tab label with optional unread suffix.
String formatInboxReceiptsTabLabel(String label, int unread) =>
    unread > 0 ? '$label ($unread)' : label;
