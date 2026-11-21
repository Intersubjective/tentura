import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_requests_port.dart';

@Injectable(
  as: ConstellationFieldRequestsPort,
  env: [Environment.test],
  order: 1,
)
class ConstellationFieldRequestsRepositoryMock
    implements ConstellationFieldRequestsPort {
  @override
  Future<List<ConstellationRequestRecord>> discoverableRequestsByIds({
    required String viewerId,
    required Set<String> beaconIds,
    required ConstellationFieldMembershipFilters filters,
  }) => Future.value(const []);
}
