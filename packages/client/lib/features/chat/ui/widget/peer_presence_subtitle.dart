import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/entity/peer_presence_entity.dart';

/// One-line status for chat app bar / peer list.
String peerPresenceSubtitle({
  required L10n l10n,
  required PeerPresenceEntity? presence,
  required bool isTyping,
}) {
  if (isTyping) {
    return l10n.chatPresenceTyping;
  }
  final p = presence;
  if (p == null) {
    return '';
  }
  if (p.status == UserPresenceStatus.online) {
    return l10n.chatPresenceOnline;
  }
  final ts = p.lastSeenAt;
  if (ts.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final diff = DateTime.now().difference(ts.toLocal());
  if (diff.inSeconds < 60) {
    return l10n.chatPresenceLastSeenJustNow;
  }
  if (diff.inMinutes < 60) {
    return l10n.chatPresenceLastSeenMinutes(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.chatPresenceLastSeenHours(diff.inHours);
  }
  return l10n.chatPresenceLastSeenDays(diff.inDays);
}
