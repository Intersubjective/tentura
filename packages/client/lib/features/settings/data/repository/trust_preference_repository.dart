import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/port/trust_preference_repository_port.dart';

import '../gql/_g/noisy_wall_enabled.req.gql.dart';
import '../gql/_g/set_noisy_wall_enabled.req.gql.dart';

@LazySingleton(
  as: TrustPreferenceRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class TrustPreferenceRepository implements TrustPreferenceRepositoryPort {
  const TrustPreferenceRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'TrustPreference';

  @override
  Future<bool> fetchNoisyWallEnabled() => _remoteApiService
      .request(GNoisyWallEnabledReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).noisyWallEnabled);

  @override
  Future<bool> setNoisyWallEnabled({required bool enabled}) => _remoteApiService
      .request(GSetNoisyWallEnabledReq((r) => r..vars.enabled = enabled))
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label).setNoisyWallEnabled);
}
