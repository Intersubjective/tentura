/// One line item rendered in a notification or digest email.
class EmailNotificationItem {
  const EmailNotificationItem({
    required this.title,
    required this.body,
    required this.url,
    this.subject,
    this.excerpt,
  });

  final String title;
  final String body;
  final String url;

  /// Mail subject when it differs from [title]. Set for rendered copy, whose
  /// [title] is then the entity label (or headline), shown as a link, and
  /// [excerpt] the sender's own words, quoted under [body].
  final String? subject;
  final String? excerpt;
}

/// A single, high-stakes "asked of you" email (immediate send).
class EmailNotificationContent {
  const EmailNotificationContent({
    required this.item,
    required this.unsubscribeUrl,
    required this.managePrefsUrl,
  });

  final EmailNotificationItem item;
  final String unsubscribeUrl;
  final String managePrefsUrl;
}

/// One grouped section of a digest (e.g. "Waiting on you").
class EmailDigestSection {
  const EmailDigestSection({
    required this.heading,
    required this.items,
  });

  final String heading;
  final List<EmailNotificationItem> items;
}

/// The batched "what's waiting / what moved" digest email.
class EmailDigestContent {
  const EmailDigestContent({
    required this.sections,
    required this.unsubscribeUrl,
    required this.managePrefsUrl,
  });

  final List<EmailDigestSection> sections;
  final String unsubscribeUrl;
  final String managePrefsUrl;

  int get totalItems => sections.fold(0, (sum, s) => sum + s.items.length);
}
