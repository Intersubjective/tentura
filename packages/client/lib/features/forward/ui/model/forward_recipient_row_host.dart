import 'package:flutter/widgets.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/availability_line.dart';
import 'package:tentura/ui/utils/profile_presence_line.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

/// D19 host inventory — every [ForwardRecipientRow] must pass one explicitly.
enum ForwardRecipientRowHost {
  pickerStandard,
  pickerLineage,
  pickerBand,
  pickerSearch,
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
}

bool forwardRecipientAlreadyIneligibleInvolvement(CandidateInvolvement i) =>
    i == CandidateInvolvement.author ||
    i == CandidateInvolvement.declined ||
    i == CandidateInvolvement.helpOffered ||
    i == CandidateInvolvement.withdrawn ||
    i == CandidateInvolvement.forwardedByMe;

bool forwardRecipientPauseReplacesRelation(CandidateInvolvement i) =>
    i == CandidateInvolvement.unseen ||
    i == CandidateInvolvement.forwarded ||
    i == CandidateInvolvement.watching;

String forwardRecipientRelationLabel(L10n l10n, ForwardCandidate candidate) {
  if (candidate.involvement != CandidateInvolvement.declined &&
      candidate.involvement != CandidateInvolvement.author &&
      !candidate.isReachable) {
    return l10n.notReachable;
  }
  return switch (candidate.involvement) {
    CandidateInvolvement.declined => l10n.forwardDeclined,
    CandidateInvolvement.author => l10n.forwardAuthor,
    CandidateInvolvement.forwardedByMe =>
      candidate.myForwardNote != null && candidate.myForwardNote!.isNotEmpty
          ? l10n.forwardedByMeWithNote(candidate.myForwardNote!)
          : l10n.forwardedByMe,
    CandidateInvolvement.forwarded => l10n.forwardAlreadyForwarded,
    CandidateInvolvement.watching => l10n.forwardWatching,
    CandidateInvolvement.helpOffered => l10n.forwardHelpOffered,
    CandidateInvolvement.withdrawn => l10n.forwardWithdrawn,
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

ForwardRecipientLine2 computeForwardRecipientLine2({
  required ForwardCandidate candidate,
  required ForwardRecipientRowHost host,
  required DateTime todayUtc,
  required L10n l10n,
  required Locale locale,
  String? tierEvidenceLabel,
  TenturaTone? tierEvidenceTone,
  bool showPresenceLine = true,
}) {
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

  final relationLabel = forwardRecipientRelationLabel(l10n, candidate);
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
          assert(resumeOn != null);
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

  return ForwardRecipientLine2(
    presenceOrAvailabilityLine: presence,
    presenceOrAvailabilityTone: TenturaTone.neutral,
    relationLabel: relationLabel,
    relationTone: relationTone,
    forwardedByMeWithNote: forwardedByMeWithNote,
  );
}

bool forwardRecipientCheckboxEnabled({
  required ForwardCandidate candidate,
  required DateTime todayUtc,
  required bool isSelected,
}) =>
    candidate.canForwardToOn(todayUtc) || isSelected;
