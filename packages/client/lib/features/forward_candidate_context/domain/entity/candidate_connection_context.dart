import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura/domain/entity/image_entity.dart';

part 'candidate_connection_context.freezed.dart';

enum CandidateConnectionContextStatus { path, longPath, unavailable }

enum CandidateConnectionNodeKind { viewer, candidate, person, unavailable }

@freezed
abstract class CandidateConnectionContext with _$CandidateConnectionContext {
  const factory CandidateConnectionContext({
    required CandidateConnectionContextStatus status,
    @Default([]) List<CandidateConnectionNode> nodes,
  }) = _CandidateConnectionContext;
}

@freezed
abstract class CandidateConnectionNode with _$CandidateConnectionNode {
  const factory CandidateConnectionNode({
    required CandidateConnectionNodeKind kind,
    String? id,
    String? displayName,
    ImageEntity? image,
  }) = _CandidateConnectionNode;
}
