import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/inbox_provenance.dart';

/// One-line “why me” copy for a forward offer (uses existing inbox l10n).
String inboxForwardWhyLine(InboxProvenance provenance, L10n l10n) {
  final senders = provenance.senders;
  if (senders.isEmpty) return '';
  final first = senders.first;
  final name = first.displayName.trim().isNotEmpty
      ? first.displayName.trim()
      : first.id;
  final total = provenance.totalDistinctSenders;
  final extra = total > 1 ? total - 1 : 0;
  if (extra > 0) {
    return l10n.inboxFromForwarderPlus(name, extra);
  }
  return l10n.inboxFromForwarder(name);
}
