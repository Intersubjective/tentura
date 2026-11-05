import 'package:flutter/widgets.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';
import '../../domain/entity/forward_reach.dart';

/// D19 host inventory — every [ForwardRecipientRow] must pass one explicitly.
enum ForwardRecipientRowHost {
  pickerStandard,
  pickerLineage,
  pickerBand,
  lineagePreview,
}

extension ForwardRecipientRowHostAvailability on ForwardRecipientRowHost {
  bool get showsAvailability => this != ForwardRecipientRowHost.lineagePreview;
}

/// Computed line-2 slots for recipient rows (architecture §9.4).
class ForwardRecipientLine2 {
  const ForwardRecipientLine2({
    this.tierEvidenceLabel,
    this.tierEvidenceTone,
    this.presenceOrAvailabilityLine,
    this.presenceOrAvailabilityTone,
    this.presenceOrAvailabilityUsesStatusText = false,
    this.relationLabel,
    this.relationTone,
    this.forwardedByMeWithNote = false,
    this.suppressed = false,
    this.reachViaAvatars = const [],
  });

  final String? tierEvidenceLabel;
  final TenturaTone? tierEvidenceTone;
  final String? presenceOrAvailabilityLine;
  final TenturaTone? presenceOrAvailabilityTone;
  final bool presenceOrAvailabilityUsesStatusText;
  final String? relationLabel;
  final TenturaTone? relationTone;
  final bool forwardedByMeWithNote;
  final bool suppressed;
  final List<Profile> reachViaAvatars;
}

bool forwardRecipientAlreadyIneligibleInvolvement(CandidateInvolvement i) =>
    i == CandidateInvolvement.author ||
    i == CandidateInvolvement.declined ||
    i == CandidateInvolvement.helpOffered ||
    i == CandidateInvolvement.withdrawn ||
    i == CandidateInvolvement.offerDeclinedByAuthor ||
    i == CandidateInvolvement.forwardedByMe;

bool forwardRecipientPauseReplacesRelation(CandidateInvolvement i) =>
    i == CandidateInvolvement.unseen ||
    i == CandidateInvolvement.forwarded ||
    i == CandidateInvolvement.watching;

/// [isPost]: the forwarded beacon is a Post, so its author is the Post's
/// author (#501).
///
/// [viewerIsAuthor]: the viewer wrote this Request. Someone who dismissed it
/// stays out of the picker; its author is told where they can still ask
/// them (#730: People › Invite, which carries the invitation).
String forwardRecipientRelationLabel(
  L10n l10n,
  ForwardCandidate candidate, {
  bool isPost = false,
  bool viewerIsAuthor = false,
}) {
  if (candidate.involvement != CandidateInvolvement.declined &&
      candidate.involvement != CandidateInvolvement.author &&
      !candidate.isReachable) {
    return l10n.notReachable;
  }
  return switch (candidate.involvement) {
    CandidateInvolvement.declined =>
      viewerIsAuthor && !isPost
          ? l10n.forwardDeclinedUseInvite
          : l10n.forwardDeclined,
    CandidateInvolvement.author =>
      isPost ? l10n.forwardAuthorPost : l10n.forwardAuthor,
    CandidateInvolvement.forwardedByMe =>
      candidate.myForwardNote != null && candidate.myForwardNote!.isNotEmpty
          ? l10n.forwardedByMeWithNote(candidate.myForwardNote!)
          : l10n.forwardedByMe,
    CandidateInvolvement.forwarded => l10n.forwardAlreadyForwarded,
    CandidateInvolvement.watching => l10n.forwardWatching,
    CandidateInvolvement.helpOffered => l10n.forwardHelpOffered,
    CandidateInvolvement.withdrawn => l10n.forwardWithdrawn,
    CandidateInvolvement.offerDeclinedByAuthor =>
      l10n.forwardOfferDeclinedByAuthor,
    CandidateInvolvement.unseen => l10n.forwardFilterUnseen,
  };
}

TenturaTone forwardRecipientRelationTone(
  ForwardCandidate candidate, {
  required DateTime todayUtc,
}) {
  if (candidate.involvement != CandidateInvolvement.declined &&
      candidate.involvement != CandidateInvolvement.author &&
      !candidate.isReachable) {
    return TenturaTone.neutral;
  }
  if (candidate.involvement == CandidateInvolvement.declined ||
      candidate.involvement == CandidateInvolvement.author) {
    return TenturaTone.warn;
  }
  if (candidate.involvement == CandidateInvolvement.unseen) {
    return candidate.canForwardToOn(todayUtc)
        ? TenturaTone.good
        : TenturaTone.neutral;
  }
  return TenturaTone.warn;
}

bool _hostShowsForwardReachReason({
  required ForwardRecipientRowHost host,
  required ForwardCandidate candidate,
}) {
  if (candidate.reach == null) {
    return false;
  }
  return switch (host) {
    ForwardRecipientRowHost.pickerStandard ||
    ForwardRecipientRowHost.pickerLineage => true,
    _ => false,
  };
}

String forwardReachReasonLabel(L10n l10n, ForwardCandidate candidate) {
  final reach = candidate.reach!;
  return switch (reach.kind) {
    ForwardReachKind.direct => l10n.forwardReachYouTrustThem,
    ForwardReachKind.viaConnection => _forwardReachViaLabel(l10n, candidate),
    ForwardReachKind.sharedRequest => l10n.forwardReachSharedRequest(
      reach.sharedRequest?.title ?? '',
    ),
    ForwardReachKind.wider => l10n.forwardReachDistantConnection,
  };
}

String _forwardReachViaLabel(L10n l10n, ForwardCandidate candidate) {
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

ForwardRecipientLine2? _forwardReachReasonLine2({
  required ForwardCandidate candidate,
  required ForwardRecipientRowHost host,
  required L10n l10n,
  required Locale locale,
  required DateTime todayUtc,
}) {
  if (!_hostShowsForwardReachReason(host: host, candidate: candidate)) {
    return null;
  }
  if (!candidate.isReachable ||
      forwardRecipientAlreadyIneligibleInvolvement(candidate.involvement)) {
    return null;
  }
  if (candidate.involvement != CandidateInvolvement.unseen &&
      candidate.involvement != CandidateInvolvement.forwarded &&
      candidate.involvement != CandidateInvolvement.watching) {
    return null;
  }
  if (host.showsAvailability &&
      candidate.profile.availability.effectiveOn(todayUtc) ==
          AvailabilityView.paused &&
      forwardRecipientPauseReplacesRelation(candidate.involvement)) {
    return null;
  }

  final label = forwardReachReasonLabel(l10n, candidate);
  final reach = candidate.reach!;
  if (reach.kind == ForwardReachKind.direct) {
    final presence = profilePresenceDisplayLine(
      l10n: l10n,
      locale: locale,
      status: candidate.profile.presenceStatus,
      lastSeenAt: candidate.profile.presenceLastSeenAt,
    );
    if (presence.isNotEmpty) {
      return ForwardRecipientLine2(
        presenceOrAvailabilityLine: l10n.forwardReachYouTrustThemWithPresence(
          presence,
        ),
        presenceOrAvailabilityTone: TenturaTone.good,
      );
    }
    return ForwardRecipientLine2(
      relationLabel: label,
      relationTone: TenturaTone.good,
    );
  }
  if (reach.kind == ForwardReachKind.viaConnection) {
    return ForwardRecipientLine2(
      relationLabel: label,
      relationTone: TenturaTone.info,
      reachViaAvatars: candidate.reachViaProfiles,
    );
  }
  return ForwardRecipientLine2(
    relationLabel: label,
    relationTone: reach.kind == ForwardReachKind.wider
        ? TenturaTone.neutral
        : TenturaTone.info,
  );
}

ForwardRecipientLine2 computeForwardRecipientLine2({
  required ForwardCandidate candidate,
  required ForwardRecipientRowHost host,
  required DateTime todayUtc,
  required L10n l10n,
  required Locale locale,
  String? tierEvidenceLabel,
  TenturaTone? tierEvidenceTone,
  bool showPresenceLine = true,
  bool isPost = false,
  bool viewerIsAuthor = false,
}) {
  final reachLine = _forwardReachReasonLine2(
    candidate: candidate,
    host: host,
    l10n: l10n,
    locale: locale,
    todayUtc: todayUtc,
  );
  if (reachLine != null) {
    return reachLine;
  }

  // A paused person cannot be picked; say why even where a tier label or
  // the suppressed exploration line would otherwise take the slot.
  if (host.showsAvailability &&
      candidate.isReachable &&
      !forwardRecipientAlreadyIneligibleInvolvement(candidate.involvement) &&
      forwardRecipientPauseReplacesRelation(candidate.involvement) &&
      candidate.profile.availability.effectiveOn(todayUtc) ==
          AvailabilityView.paused) {
    final resumeOn = candidate.profile.availability.resumeOn;
    assert(resumeOn != null, 'paused availability must carry resumeOn');
    return ForwardRecipientLine2(
      presenceOrAvailabilityLine: l10n.availabilityPausedUntil(
        availabilityWhenLabel(l10n, resumeOn!, todayUtc),
      ),
      presenceOrAvailabilityTone: TenturaTone.neutral,
      presenceOrAvailabilityUsesStatusText: true,
    );
  }

  if (tierEvidenceLabel != null) {
    return ForwardRecipientLine2(
      tierEvidenceLabel: tierEvidenceLabel,
      tierEvidenceTone: tierEvidenceTone ?? TenturaTone.info,
    );
  }

  if (!showPresenceLine) {
    return const ForwardRecipientLine2(suppressed: true);
  }

  final presence = profilePresenceDisplayLine(
    l10n: l10n,
    locale: locale,
    status: candidate.profile.presenceStatus,
    lastSeenAt: candidate.profile.presenceLastSeenAt,
  );
  final presenceHidden = presence.isEmpty;

  final relationLabel = forwardRecipientRelationLabel(
    l10n,
    candidate,
    isPost: isPost,
    viewerIsAuthor: viewerIsAuthor,
  );
  final relationTone = forwardRecipientRelationTone(
    candidate,
    todayUtc: todayUtc,
  );
  final forwardedByMeWithNote =
      candidate.involvement == CandidateInvolvement.forwardedByMe &&
      candidate.myForwardNote != null &&
      candidate.myForwardNote!.isNotEmpty;

  final notReachable =
      candidate.involvement != CandidateInvolvement.declined &&
      candidate.involvement != CandidateInvolvement.author &&
      !candidate.isReachable;

  if (notReachable) {
    return ForwardRecipientLine2(
      relationLabel: relationLabel,
      relationTone: relationTone,
      forwardedByMeWithNote: forwardedByMeWithNote,
    );
  }

  if (forwardRecipientAlreadyIneligibleInvolvement(candidate.involvement)) {
    return ForwardRecipientLine2(
      relationLabel: relationLabel,
      relationTone: relationTone,
      forwardedByMeWithNote: forwardedByMeWithNote,
    );
  }

  if (host.showsAvailability) {
    final view = candidate.profile.availability.effectiveOn(todayUtc);
    switch (view) {
      case AvailabilityView.paused:
        if (forwardRecipientPauseReplacesRelation(candidate.involvement)) {
          final resumeOn = candidate.profile.availability.resumeOn;
          assert(resumeOn != null, 'paused availability must carry resumeOn');
          return ForwardRecipientLine2(
            presenceOrAvailabilityLine: l10n.availabilityPausedUntil(
              availabilityWhenLabel(l10n, resumeOn!, todayUtc),
            ),
            presenceOrAvailabilityTone: TenturaTone.neutral,
            presenceOrAvailabilityUsesStatusText: true,
          );
        }
        break;
      case AvailabilityView.limited:
        return ForwardRecipientLine2(
          presenceOrAvailabilityLine: l10n.availabilityLimitedTitle,
          presenceOrAvailabilityTone: TenturaTone.neutral,
          presenceOrAvailabilityUsesStatusText: true,
          relationLabel: relationLabel,
          relationTone: relationTone,
        );
      case AvailabilityView.open:
        break;
    }
  }

  if (presenceHidden) {
    return ForwardRecipientLine2(
      relationLabel: relationLabel,
      relationTone: relationTone,
      forwardedByMeWithNote: forwardedByMeWithNote,
    );
  }

  // Next to a presence line, a forwardable "Unseen" only repeats the
  // "Not yet seen" tab the row sits in (and ran into it: "Online Unseen").
  final redundantUnseen =
      candidate.involvement == CandidateInvolvement.unseen &&
      relationTone == TenturaTone.good;
  return ForwardRecipientLine2(
    presenceOrAvailabilityLine: presence,
    presenceOrAvailabilityTone: TenturaTone.neutral,
    relationLabel: redundantUnseen ? null : relationLabel,
    relationTone: relationTone,
    forwardedByMeWithNote: forwardedByMeWithNote,
  );
}

bool forwardRecipientCheckboxEnabled({
  required ForwardCandidate candidate,
  required DateTime todayUtc,
  required bool isSelected,
}) => candidate.canForwardToOn(todayUtc) || isSelected;
