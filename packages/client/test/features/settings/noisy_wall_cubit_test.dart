import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/port/trust_preference_repository_port.dart';
import 'package:tentura/features/settings/ui/bloc/noisy_wall_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeTrustPreferenceRepository implements TrustPreferenceRepositoryPort {
  bool enabled = false;
  bool failFetch = false;
  bool failSet = false;
  Completer<bool>? gate;
  final setCalls = <bool>[];

  @override
  Future<bool> fetchNoisyWallEnabled() async {
    if (gate != null) return gate!.future;
    if (failFetch) throw Exception('fetch failed');
    return enabled;
  }

  @override
  Future<bool> setNoisyWallEnabled({required bool enabled}) async {
    setCalls.add(enabled);
    if (gate != null) return gate!.future;
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

  test('closing while fetch is pending raises no StateError', () async {
    final gate = repo.gate = Completer<bool>();
    final pending = cubit.fetch();
    await cubit.close();
    gate.complete(true);
    await expectLater(pending, completes);
  });

  test('closing while fetch is pending then failing raises no StateError',
      () async {
    final gate = repo.gate = Completer<bool>();
    final pending = cubit.fetch();
    await cubit.close();
    gate.completeError(Exception('late'));
    await expectLater(pending, completes);
    expect(effects.emitted, isEmpty);
  });

  test('closing while set is pending raises no StateError', () async {
    final gate = repo.gate = Completer<bool>();
    final pending = cubit.set(enabled: true);
    await cubit.close();
    gate.complete(true);
    await expectLater(pending, completes);
  });
}
