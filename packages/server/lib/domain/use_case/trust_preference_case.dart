import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_preference_port.dart';

import '_use_case_base.dart';

/// The actor's own trust preferences. Only the noisy-contact wall switch:
/// the wall lives in the actor's frame, so only they may change it.
@Singleton(order: 2)
final class TrustPreferenceCase extends UseCaseBase {
  TrustPreferenceCase(
    this._preferences, {
    required super.env,
    required super.logger,
  });

  final TrustPreferencePort _preferences;

  Future<bool> noisyWallEnabled({required String actorId}) =>
      _preferences.noisyWallEnabled(actorId);

  Future<bool> setNoisyWallEnabled({
    required String actorId,
    required bool enabled,
  }) => _preferences.setNoisyWallEnabled(userId: actorId, enabled: enabled);
}
