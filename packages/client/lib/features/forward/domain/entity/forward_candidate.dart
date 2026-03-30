import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/profile.dart';

import 'candidate_involvement.dart';

part 'forward_candidate.freezed.dart';

@freezed
abstract class ForwardCandidate with _$ForwardCandidate {
  const factory ForwardCandidate({
    required Profile profile,
    @Default(CandidateInvolvement.unseen) CandidateInvolvement involvement,
  }) = _ForwardCandidate;

  const ForwardCandidate._();

  String get id => profile.id;

  String get title => profile.title;

  bool get isReachable => profile.isSeeingMe;

  double get mrScore => profile.score;

  bool get canForwardTo =>
      isReachable &&
      involvement != CandidateInvolvement.declined &&
      involvement != CandidateInvolvement.author;

  bool get isUnseen => involvement == CandidateInvolvement.unseen;
}
