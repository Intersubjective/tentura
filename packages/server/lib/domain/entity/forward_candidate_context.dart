import 'package:meta/meta.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';

enum ForwardCandidateContextStatus { path, longPath, unavailable }

enum ForwardCandidateConnectionNodeKind {
  viewer,
  candidate,
  person,
  unavailable,
}

/// Provenance from a bounded MeritRank graph snapshot.
///
/// A returned path is deterministic for the authorized snapshot. It is not a
/// statement about recommendation logic or the complete network.
@immutable
class ForwardCandidateContext {
  const ForwardCandidateContext({required this.status, required this.nodes});

  const ForwardCandidateContext.longPath()
    : status = ForwardCandidateContextStatus.longPath,
      nodes = const [];

  const ForwardCandidateContext.unavailable()
    : status = ForwardCandidateContextStatus.unavailable,
      nodes = const [];

  final ForwardCandidateContextStatus status;
  final List<ForwardCandidateConnectionNode> nodes;
}

@immutable
class ForwardCandidateConnectionNode {
  const ForwardCandidateConnectionNode({
    required this.kind,
    this.id,
    this.displayName,
    this.image,
  });

  final ForwardCandidateConnectionNodeKind kind;
  final String? id;
  final String? displayName;
  final ImagePublicRecord? image;
}
