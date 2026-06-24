import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';

import '../gql/_g/beacon_display_statuses.req.gql.dart';

@lazySingleton
class BeaconDisplayRepository {
  BeaconDisplayRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  Future<List<BeaconDisplayStatusDto>> fetchDisplayStatuses(
    List<String> beaconIds,
  ) async {
    if (beaconIds.isEmpty) return const [];
    final rows = await _remoteApiService
        .request(
          GBeaconDisplayStatusesReq(
            (b) => b.vars.beaconIds.replace(beaconIds),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: 'BeaconDisplayStatuses').beaconDisplayStatuses);
    return [
      for (final row in rows)
        beaconDisplayStatusFromGql({
          'beaconId': row.beaconId,
          'status': row.status,
          'phase': row.phase,
          'suggestedAction': row.suggestedAction,
          'slot2Kind': row.slot2Kind,
          'tier': row.tier,
          'reviewClosesAt': row.reviewClosesAt,
          'lastActivityAt': row.lastActivityAt,
          'lifecycleEndedAt': row.lifecycleEndedAt,
        }),
    ];
  }
}
