import 'package:tentura_server/domain/entity/forward_candidate_context.dart';

import 'gql_public_user_maps.dart';

Map<String, dynamic> forwardCandidateContextToGqlMap(
  ForwardCandidateContext context,
) => {
  'status': context.status.name,
  'nodes': context.nodes.map(_nodeToGqlMap).toList(growable: false),
};

Map<String, dynamic> _nodeToGqlMap(ForwardCandidateConnectionNode node) => {
  'kind': node.kind.name,
  'id': node.id,
  'displayName': node.displayName,
  'image': node.image == null ? null : imagePublicToGqlMap(node.image!),
};
