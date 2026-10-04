import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/port/trust_preference_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/noisy_wall_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeTrustPreferenceRepository implements TrustPreferenceRepositoryPort {
  bool enabled = false;
  bool failFetch = false;
  bool failSet = false;
  final setCalls = <bool>[];

  @override
  Future<bool> fetchNoisyWallEnabled() async {
    if (failFetch) throw Exception('fetch failed');
    return enabled;
  }

  @override
  Future<bool> setNoisyWallEnabled({required bool enabled}) async {
    setCalls.add(enabled);
    if (failSet) throw Exception('set failed');
    return this.enabled = enabled;
  }
}

void main() {
  late _FakeTrustPreferenceRepository repo;
  late FakeUiEffectPort effects;
  late NoisyWallCubit cubit;

  setUp(() {
    repo = _FakeTrustPreferenceRepository();
    effects = FakeUiEffectPort();
    cubit = NoisyWallCubit(repository: repo, effects: effects);
  });

  tearDown(() => cubit.close());

  test('starts unknown, then shows the server value', () async {
    expect(cubit.state.enabled, isNull);
    repo.enabled = true;
    await cubit.fetch();
    expect(cubit.state.enabled, isTrue);
    expect(cubit.state.isSuccess, isTrue);
  });

  test('a failed fetch stays unknown and reports the error', () async {
    repo.failFetch = true;
    await cubit.fetch();
    expect(cubit.state.enabled, isNull);
    expect(effects.emitted, isNotEmpty);
  });

  test('set stores the choice', () async {
    await cubit.fetch();
    await cubit.set(enabled: true);
    expect(repo.setCalls, [true]);
    expect(cubit.state.enabled, isTrue);
  });

  test('a refused set rolls back and reports the error', () async {
    await cubit.fetch();
    repo.failSet = true;
    await cubit.set(enabled: true);
    expect(cubit.state.enabled, isFalse);
    expect(effects.emitted, isNotEmpty);
  });
}
