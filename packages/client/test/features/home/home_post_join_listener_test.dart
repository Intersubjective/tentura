import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

import 'package:tentura/features/home/domain/entity/post_join_destination.dart';
import 'package:tentura/features/home/domain/port/post_join_beacon_handoff_port.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_post_join_listener.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

class _FakeHandoffPort implements PostJoinBeaconHandoffPort {
  _FakeHandoffPort(this._dest);

  PostJoinDestination? _dest;

  void set(PostJoinDestination? d) => _dest = d;

  @override
  PostJoinDestination? readAndClear() {
    final d = _dest;
    _dest = null;
    return d;
  }
}

class _FakeUiEffectPort implements UiEffectPort {
  final emitted = <UiEffect>[];

  @override
  Stream<UiEffect> get effects => Stream.empty();

  @override
  void emit(UiEffect effect) => emitted.add(effect);
}

class _FakeTabsRouter extends Fake implements TabsRouter {
  var activeIndex = 0;

  @override
  void setActiveIndex(int value, {bool notify = true}) {
    activeIndex = value;
  }
}

void main() {
  testWidgets('HomePostJoinListener switches to inbox and emits snackbar', (
    tester,
  ) async {
    final handoff = _FakeHandoffPort(null);
    final postJoin = PostJoinNavigationCubit();
    final effects = _FakeUiEffectPort();
    final tabsRouter = _FakeTabsRouter();

    handoff.set(
      const PostJoinDestination(
        beaconId: 'B1',
        beaconTitle: 'Help needed',
        inviterName: 'Alice',
        showSnackbar: true,
      ),
    );

    GetIt.I
      ..registerSingleton<PostJoinBeaconHandoffPort>(handoff)
      ..registerSingleton<PostJoinNavigationCubit>(postJoin)
      ..registerSingleton<UiEffectPort>(effects);

    addTearDown(GetIt.I.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: HomePostJoinListener(
          tabsRouter: tabsRouter,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pump();

    expect(
      tabsRouter.activeIndex,
      HomeTabSpec.forTab(HomeTab.inbox).index,
    );
    expect(
      effects.emitted.whereType<ShowMessage>().length,
      1,
    );
  });
}
