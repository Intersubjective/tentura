import 'package:meta/meta.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';

@immutable
class ForwardCandidateGraphSnapshot {
  const ForwardCandidateGraphSnapshot({
    required this.candidateEligible,
    required this.edges,
    required this.people,
    this.candidateJoinedAt,
  });

  const ForwardCandidateGraphSnapshot.unavailable()
    : candidateEligible = false,
      edges = const [],
      people = const {},
      candidateJoinedAt = null;

  final bool candidateEligible;
  final List<ForwardCandidateGraphEdge> edges;
  final Map<String, ForwardCandidatePersonProjection> people;
  final DateTime? candidateJoinedAt;
}

@immutable
class ForwardCandidateGraphEdge {
  const ForwardCandidateGraphEdge(this.a, this.b, {this.weight = 1});

  final String a;
  final String b;
  final double weight;
}

@immutable
class ForwardCandidatePersonProjection {
  const ForwardCandidatePersonProjection({
    required this.id,
    required this.displayName,
    this.image,
  });

  final String id;
  final String displayName;
  final ImagePublicRecord? image;
}
