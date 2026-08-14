import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';

import '../forward_draft_policy.dart';
import 'candidate_involvement.dart';

part 'person_forward_row.freezed.dart';

enum PersonForwardBlock {
  none,
  notOpen,
  alreadySent,
  alreadyHelping,
  declined,
  withdrawn,
  theirOwn,
}

@freezed
abstract class PersonForwardRow with _$PersonForwardRow {
  const factory PersonForwardRow({
    required Beacon beacon,
    required CandidateInvolvement involvement,
    @Default(PersonForwardBlock.none) PersonForwardBlock block,
    String? forwardEdgeId,
    DateTime? recipientReadAt,
    @Default(false) bool hasOnwardChild,
    @Default(false) bool recipientDeclined,
    @Default(false) bool recipientHasActiveHelpOffer,
  }) = _PersonForwardRow;

  const PersonForwardRow._();

  bool get isEligible => block == PersonForwardBlock.none;

  bool get isForwardEdgeCancellable =>
      forwardEdgeId != null &&
      forwardEdgeIsCancellable(
        recipientReadAt: recipientReadAt,
        hasOnwardChild: hasOnwardChild,
        recipientHasActiveHelpOffer: recipientHasActiveHelpOffer,
        recipientDeclined: recipientDeclined,
      );

  static PersonForwardBlock blockFor(
    CandidateInvolvement involvement,
    BeaconStatus status,
  ) {
    if (!status.allowsForward) {
      return PersonForwardBlock.notOpen;
    }
    return switch (involvement) {
      CandidateInvolvement.forwardedByMe => PersonForwardBlock.alreadySent,
      CandidateInvolvement.helpOffered => PersonForwardBlock.alreadyHelping,
      CandidateInvolvement.declined => PersonForwardBlock.declined,
      CandidateInvolvement.withdrawn => PersonForwardBlock.withdrawn,
      CandidateInvolvement.author => PersonForwardBlock.theirOwn,
      CandidateInvolvement.unseen ||
      CandidateInvolvement.forwarded ||
      CandidateInvolvement.watching => PersonForwardBlock.none,
    };
  }
}
