import 'package:meta/meta.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';

@immutable
class ForwardCandidateGraphSnapshot {
  const ForwardCandidateGraphSnapshot({
    required this.candidateEligible,
    required this.edges,
    required this.people,
  });

  const ForwardCandidateGraphSnapshot.unavailable()
    : candidateEligible = false,
      edges = const [],
      people = const {};

  final bool candidateEligible;
  final List<ForwardCandidateGraphEdge> edges;
  final Map<String, ForwardCandidatePersonProjection> people;
}

@immutable
class ForwardCandidateGraphEdge {
  const ForwardCandidateGraphEdge(this.a, this.b);

  final String a;
  final String b;
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
