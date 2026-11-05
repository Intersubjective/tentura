import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_candidate.dart';
import 'package:tentura/features/forward/domain/entity/forward_reach.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/capability_tag_presenter.dart';
import 'package:tentura/ui/utils/profile_member_since.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';

import '../../domain/entity/candidate_connection_context.dart';
import '../bloc/forward_candidate_context_state.dart';

/// Recent join copy uses relative tenure; older joins use month-year only (#440).
const kForwardCandidateJoinedRecentMaxDays = 90;

/// Joined / member-since segment for the sheet header, or null when hidden.
String? forwardCandidateSheetJoinedLabel({
  required L10n l10n,
  required DateTime joinedAt,
  required DateTime now,
}) {
  final days = profileTenureCalendarDays(joinedAt: joinedAt, now: now);
  if (days < kForwardCandidateJoinedRecentMaxDays) {
    final relative = profileTenureDurationLabel(
      l10n: l10n,
      joinedAt: joinedAt,
      now: now,
    );
    return l10n.friendsInviteJoinedRelative(relative);
  }
  final formatted = DateFormat.yMMM(l10n.localeName).format(joinedAt.toLocal());
  return l10n.forwardCandidateMemberSinceShort(formatted);
}

String forwardCandidateSheetHeaderSubline({
  required L10n l10n,
  required Locale locale,
  required Profile profile,
  required ForwardCandidateContextPhase phase,
  DateTime? joinedAt,
  DateTime? now,
}) {
  final presence = profilePresenceDisplayLine(
    l10n: l10n,
    locale: locale,
    status: profile.presenceStatus,
    lastSeenAt: profile.presenceLastSeenAt,
  );
  final showJoined =
      joinedAt != null &&
      phase != ForwardCandidateContextPhase.loading &&
      phase != ForwardCandidateContextPhase.unavailable;
  final joinedPart = showJoined
      ? forwardCandidateSheetJoinedLabel(
          l10n: l10n,
          joinedAt: joinedAt,
          now: now ?? DateTime.now(),
        )
      : null;
  if (joinedPart != null && presence.isNotEmpty) {
    return '$joinedPart · $presence';
  }
  if (joinedPart != null) return joinedPart;
  if (presence.isNotEmpty) return presence;
  return profile.canonicalSecondaryLabel;
}

DateTime? forwardCandidateSheetJoinedAt({
  required Profile profile,
  required ForwardCandidateContextPhase phase,
  CandidateConnectionContext? connectionContext,
}) {
  if (phase == ForwardCandidateContextPhase.direct) {
    return profile.joinedAt;
  }
  return connectionContext?.candidateJoinedAt ?? profile.joinedAt;
}

String forwardReachVouchedLabel(L10n l10n, ForwardCandidate candidate) {
  final via = candidate.reachViaProfiles;
  final total = candidate.reachViaCount;
  if (via.isEmpty || total <= 0) {
    return l10n.forwardReachDistantConnection;
  }
  final first = via.first.shownName.trim().isEmpty
      ? via.first.displayName
      : via.first.shownName;
  if (total == 1) {
    return l10n.forwardReachVouchedByOne(first);
  }
  if (total == 2 && via.length >= 2) {
    final second = via[1].shownName.trim().isEmpty
        ? via[1].displayName
        : via[1].shownName;
    return l10n.forwardReachVouchedByTwo(first, second);
  }
  final others = total - 1;
  return l10n.forwardReachVouchedByOneAndOthers(first, others);
}

bool forwardCandidateShowsWiderPath(ForwardCandidate candidate) =>
    candidate.reach?.kind == ForwardReachKind.wider ||
    candidate.effectiveReachKind == ForwardReachKind.wider;

Profile profileFromConnectionNode(CandidateConnectionNode node) => Profile(
  id: node.id ?? '',
  displayName: node.displayName ?? '',
  image: node.image,
);

String? forwardCandidateMatchesLine({
  required L10n l10n,
  required Iterable<String> requiredSlugs,
  required Iterable<String> candidateSlugs,
}) {
  final required = {
    for (final s in requiredSlugs)
      if (s.trim().isNotEmpty) s.trim(),
  };
  if (required.isEmpty) return null;
  final labels = <String>[];
  for (final slug in candidateSlugs) {
    if (!required.contains(slug.trim())) continue;
    final tag = CapabilityTag.fromSlug(slug.trim());
    labels.add(tag?.labelOf(l10n) ?? slug.trim());
  }
  if (labels.isEmpty) return null;
  return l10n.forwardCandidateMatchesNamed(labels.join(', '));
}
