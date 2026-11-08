import 'package:built_collection/built_collection.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/port/constellation_new_people_port.dart';
import '../gql/_g/constellation_acknowledge_new.req.gql.dart';

@LazySingleton(
  as: ConstellationNewPeoplePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ConstellationNewPeopleRepository
    implements ConstellationNewPeoplePort {
  ConstellationNewPeopleRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  @override
  Future<void> acknowledgeNew(Iterable<String> peerIds) async {
    final ids = peerIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }
    await _remoteApiService
        .request(
          GConstellationAcknowledgeNewReq(
            (b) => b.vars.peerIds.replace(BuiltList<String>(ids)),
          ),
        )
        .firstLinkResponse(label: 'ConstellationAcknowledgeNew')
        .then(
          (response) => response
              .dataOrThrow(label: 'ConstellationAcknowledgeNew')
              .constellationAcknowledgeNew,
        );
  }
}
