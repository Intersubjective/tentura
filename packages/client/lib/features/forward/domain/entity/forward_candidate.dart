import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';

import 'candidate_involvement.dart';
import 'lineage_suggestion_group.dart';

part 'forward_candidate.freezed.dart';

@freezed
abstract class ForwardCandidate with _$ForwardCandidate {
  const factory ForwardCandidate({
    required Profile profile,
    @Default(CandidateInvolvement.unseen) CandidateInvolvement involvement,
    String? myForwardNote,
    String? forwardEdgeId,
    @Default([]) List<String> topCapabilities,
    DateTime? recipientReadAt,
    LineageSuggestionGroup? lineageGroup,
    String? lineageReasonCode,
    String? lineageReasonArg,
    @Default(false) bool lineageAutoSelect,
  }) = _ForwardCandidate;

  const ForwardCandidate._();

  String get id => profile.id;

  String get displayName => profile.displayName;

  bool get isReachable => profile.isMutuallyVisible;

  double get mrScore => profile.score;

  bool canForwardToOn(DateTime todayUtc) =>
      isReachable &&
      !profile.availability.blocksNewRequestsOn(todayUtc) &&
      involvement != CandidateInvolvement.forwardedByMe &&
      involvement != CandidateInvolvement.author &&
      involvement != CandidateInvolvement.declined &&
      involvement != CandidateInvolvement.helpOffered &&
      involvement != CandidateInvolvement.withdrawn;

  bool get canForwardTo => canForwardToOn(availabilityTodayUtc());

  bool get isUnseen => involvement == CandidateInvolvement.unseen;
}
