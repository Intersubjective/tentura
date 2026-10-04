import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/beacon_member_webs_repository_port.dart';

@Injectable(
  as: BeaconMemberWebsRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class BeaconMemberWebsRepositoryMock implements BeaconMemberWebsRepositoryPort {
  @override
  Future<List<ConstellationMemberWebRecord>> memberWebs({
    required String beaconId,
    required String viewerId,
    required String context,
    required bool includeForwarded,
  }) => Future.value(const []);
}
