import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_preference_port.dart';

@Injectable(
  as: TrustPreferencePort,
  env: [Environment.test],
  order: 1,
)
class TrustPreferenceRepositoryMock implements TrustPreferencePort {
  @override
  Future<bool> noisyWallEnabled(String userId) => Future.value(false);

  @override
  Future<bool> setNoisyWallEnabled({
    required String userId,
    required bool enabled,
  }) => Future.value(enabled);
}
