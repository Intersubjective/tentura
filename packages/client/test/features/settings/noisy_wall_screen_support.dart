import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/trust_preference_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

/// In-memory [TrustPreferenceRepositoryPort] for screens that host the
/// noisy-wall switch.
class FakeTrustPreferenceRepository implements TrustPreferenceRepositoryPort {
  FakeTrustPreferenceRepository({this.enabled = false});

  bool enabled;

  @override
  Future<bool> fetchNoisyWallEnabled() async => enabled;

  @override
  Future<bool> setNoisyWallEnabled({required bool enabled}) async =>
      this.enabled = enabled;
}

/// Registers what the settings screen's noisy-wall switch resolves from
/// GetIt; returns the matching teardown.
void Function() registerNoisyWallForScreenTest([
  FakeTrustPreferenceRepository? repository,
]) {
  final getIt = GetIt.I;
  final ownRepo = !getIt.isRegistered<TrustPreferenceRepositoryPort>();
  final ownEffects = !getIt.isRegistered<UiEffectPort>();
  if (ownRepo) {
    getIt.registerSingleton<TrustPreferenceRepositoryPort>(
      repository ?? FakeTrustPreferenceRepository(),
    );
  }
  if (ownEffects) getIt.registerSingleton<UiEffectPort>(FakeUiEffectPort());
  return () {
    if (ownRepo && getIt.isRegistered<TrustPreferenceRepositoryPort>()) {
      getIt.unregister<TrustPreferenceRepositoryPort>();
    }
    if (ownEffects && getIt.isRegistered<UiEffectPort>()) {
      getIt.unregister<UiEffectPort>();
    }
  };
}
