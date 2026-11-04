import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/post_summary.dart';

/// Builds the «N people · M haven't opened · K declined» line; null when omitted.
String? postConversationParticipantsLine(L10n l10n, PostSummary post) {
  if (post.participantCount == 0 &&
      post.notOpenedCount == 0 &&
      post.myDeclinedForwardCount == 0) {
    return l10n.postConversationOnlyYou;
  }
  final parts = <String>[
    if (post.participantCount > 0)
      l10n.postConversationPeople(post.participantCount),
    if (post.notOpenedCount > 0)
      l10n.postConversationNotOpened(post.notOpenedCount),
    if (post.myDeclinedForwardCount > 0)
      l10n.postConversationDeclined(post.myDeclinedForwardCount),
  ];
  return parts.isEmpty ? l10n.postConversationOnlyYou : parts.join(' · ');
}

bool postConversationShowsParticipantsLine(PostSummary post) =>
    post.participantCount > 0 ||
    post.notOpenedCount > 0 ||
    post.myDeclinedForwardCount > 0 ||
    post.previewParticipants.isNotEmpty ||
    (post.participantCount == 0 &&
        post.notOpenedCount == 0 &&
        post.myDeclinedForwardCount == 0);
