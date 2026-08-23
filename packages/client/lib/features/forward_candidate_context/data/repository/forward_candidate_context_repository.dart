import 'package:injectable/injectable.dart';
import 'package:tentura/data/model/image_model_v2.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/candidate_connection_context.dart';
import '../../domain/port/forward_candidate_context_repository_port.dart';
import '../gql/_g/forward_candidate_context_fetch.data.gql.dart';
import '../gql/_g/forward_candidate_context_fetch.req.gql.dart';

@LazySingleton(
  as: ForwardCandidateContextRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ForwardCandidateContextRepository
    implements ForwardCandidateContextRepositoryPort {
  ForwardCandidateContextRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) => _remoteApiService
      .request(
        GForwardCandidateContextFetchReq(
          (builder) => builder
            ..vars.candidateId = candidateId
            ..vars.context = context,
        ),
      )
      .firstWhere((response) => response.dataSource == DataSource.Link)
      .then((response) {
        final payload = response
            .dataOrThrow(
              label: 'ForwardCandidateContextFetch',
            )
            .forwardCandidateContext;
        return CandidateConnectionContext(
          status: CandidateConnectionContextStatus.values.byName(
            payload.status,
          ),
          nodes: [for (final node in payload.nodes) _toEntity(node)],
        );
      });
}

CandidateConnectionNode _toEntity(
  GForwardCandidateContextFetchData_forwardCandidateContext_nodes node,
) => CandidateConnectionNode(
  kind: CandidateConnectionNodeKind.values.byName(node.kind),
  id: node.id,
  displayName: node.displayName,
  image: (node.image as ImageModelV2?)?.asEntity,
);
