import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/features/capability/ui/bloc/routing_mute_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeCapabilityRepository implements CapabilityRepositoryPort {
  _FakeCapabilityRepository({this.mutedSlugs = const []});

  List<String> mutedSlugs;
  bool failSetMute = false;

  String? lastMuteSlug;
  bool? lastMuteValue;
  int setMuteCalls = 0;

  @override
  Future<List<String>> fetchMyRoutingTags() async =>
      List<String>.from(mutedSlugs);

  @override
  Future<void> setRoutingMute({
    required String slug,
    required bool muted,
  }) async {
    setMuteCalls++;
    lastMuteSlug = slug;
    lastMuteValue = muted;
    if (failSetMute) {
      throw Exception('boom');
    }
    if (muted) {
      if (!mutedSlugs.contains(slug)) {
        mutedSlugs = [...mutedSlugs, slug];
      }
    } else {
      mutedSlugs = mutedSlugs.where((s) => s != slug).toList();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RoutingMuteCubit testCubit(
  CapabilityRepositoryPort repo, {
  FakeUiEffectPort? effects,
}) =>
    RoutingMuteCubit(
      repository: repo,
      effects: effects ?? FakeUiEffectPort(),
    );

void main() {
  test('fetch loads the muted slug set', () async {
    final repo = _FakeCapabilityRepository(mutedSlugs: ['transport', 'food']);
    final cubit = testCubit(repo);
    await cubit.fetch();
    expect(cubit.state.status, isA<StateIsSuccess>());
    expect(cubit.state.mutedSlugs, {'transport', 'food'});
    await cubit.close();
  });

  test('toggleMute persists optimistically and calls setRoutingMute', () async {
    final repo = _FakeCapabilityRepository();
    final cubit = testCubit(repo);
    await cubit.fetch();

    await cubit.toggleMute(slug: 'transport', muted: true);
    expect(cubit.state.mutedSlugs, contains('transport'));
    expect(repo.setMuteCalls, 1);
    expect(repo.lastMuteSlug, 'transport');
    expect(repo.lastMuteValue, isTrue);

    await cubit.toggleMute(slug: 'transport', muted: false);
    expect(cubit.state.mutedSlugs, isNot(contains('transport')));
    expect(repo.setMuteCalls, 2);
    expect(repo.lastMuteValue, isFalse);
    await cubit.close();
  });

  test('reverts muted slug and emits ShowError when setRoutingMute fails', () async {
    final repo = _FakeCapabilityRepository()..failSetMute = true;
    final effects = FakeUiEffectPort();
    final cubit = testCubit(repo, effects: effects);
    await cubit.fetch();

    await cubit.toggleMute(slug: 'transport', muted: true);
    expect(cubit.state.mutedSlugs, isEmpty);
    expect(effects.emitted.whereType<ShowError>(), isNotEmpty);
    await cubit.close();
  });
}
