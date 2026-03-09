import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/polling_model.dart';
import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/polling.dart';

import '../../domain/entity/polling_result.dart';
import '../gql/_g/polling_act.req.gql.dart';
import '../gql/_g/polling_results_by_id.req.gql.dart';

@lazySingleton
class PollingRepository {
  static const _label = 'Polling';

  PollingRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<void> vote({
    required String pollingId,
    required String variantId,
  }) => _remoteApiService
      .request(
        GPollingActReq(
          (b) => b.vars
            ..pollingId = pollingId
            ..variantId = variantId,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).pollingAct);

  Future<({Polling polling, List<PollingResult> results})> fetchResults({
    required String pollingId,
  }) async {
    final result = await _remoteApiService
        .request(
          GPollingResultsByIdReq((b) => b.vars.id = pollingId),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));

    final polling = (result.polling_by_pk! as PollingModel).toEntity(
      author: (result.polling_by_pk!.author as UserModel).toEntity(),
    );

    final pollingResults = result.polling_results
        .map(
          (e) => (
            pollingVariantId: e.dst!,
            immediateResult: double.parse(e.dst_score!.value),
            finalResult: double.parse(e.src_score!.value),
            percentageVoted: e.dst_cluster_score!,
            votesCount: e.src_cluster_score!,
          ),
        )
        .toList();
    return (polling: polling, results: pollingResults);
  }
}
