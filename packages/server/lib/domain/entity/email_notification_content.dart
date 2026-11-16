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

/// One entry of a digest section.
sealed class EmailDigestEntry {
  const EmailDigestEntry({required this.url});

  final String url;

  int get lineCount;
}

/// Events about one Request or Post: [label] (linked to [url]) over one line
/// per event, newest first.
final class EmailDigestGroup extends EmailDigestEntry {
  const EmailDigestGroup({
    required this.label,
    required this.lines,
    required super.url,
  });

  final String label;
  final List<String> lines;

  @override
  int get lineCount => lines.length;
}

/// An event shown on its own (`headline — sentence`): its Request or Post is
/// not readable, or it has none.
final class EmailDigestLine extends EmailDigestEntry {
  const EmailDigestLine({required this.text, required super.url});

  final String text;

  @override
  int get lineCount => 1;
}

/// One section of a digest (e.g. "Waiting on you").
class EmailDigestSection {
  const EmailDigestSection({
    required this.heading,
    required this.entries,
  });

  final String heading;
  final List<EmailDigestEntry> entries;
}

/// The batched "what's waiting / what moved" digest email.
class EmailDigestContent {
  const EmailDigestContent({
    required this.sections,
    required this.unsubscribeUrl,
    required this.managePrefsUrl,
    this.lockScreenSafe = false,
  });

  final List<EmailDigestSection> sections;
  final String unsubscribeUrl;
  final String managePrefsUrl;

  /// The recipient asked for redacted notifications: the subject names
  /// nothing.
  final bool lockScreenSafe;

  int get totalItems => sections.fold(
    0,
    (sum, s) => s.entries.fold(sum, (n, e) => n + e.lineCount),
  );
}
