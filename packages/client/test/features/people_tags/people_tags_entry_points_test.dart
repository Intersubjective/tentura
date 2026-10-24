import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/port/attention_reconcile_port.dart';
import 'package:tentura/domain/port/trust_preference_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/port/people_tags_repository_port.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/screen/people_tags_screen.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/settings/ui/screen/settings_screen.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../../support/optional_gate_call.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

class _FakeAuthCubit extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(updatedAt: DateTime(2026), currentAccountId: 'U1');

  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _FakeSettingsCubit extends Fake implements SettingsCubit {
  @override
  SettingsState get state =>
      const SettingsState(visibleVersion: 'test', introEnabled: false);

  @override
  Stream<SettingsState> get stream => const Stream.empty();

  @override
  Future<String?> tryGetCurrentAccountSeed() async => null;
}

class _FakeTrustPreferences extends Fake
    implements TrustPreferenceRepositoryPort {
  @override
  Future<bool> fetchNoisyWallEnabled() async => false;
}

class _FakeAttentionReconcile extends Fake implements AttentionReconcilePort {}

class _RecordingRouter extends Fake implements StackRouter {
  final pushed = <PageRouteInfo>[];

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushed.add(route);
    return null;
  }
}

final class _EmptyPeopleTagsRepository implements PeopleTagsRepositoryPort {
  @override
  Future<List<PersonTag>> personTags() async => const [];

  @override
  Future<List<PersonTagMembers>> personTagMemberships() async => const [];

  @override
  Future<List<PersonAutoTag>> personAutoTags() async => const [];

  @override
  Future<PersonTagSuggestionState> personTagSuggestionState() async =>
      const PersonTagSuggestionState(canSuggest: true, disabled: false);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late TestRealtimeSyncPort realtimePort;
  late PeopleTagsCase peopleTags;

  setUp(() async {
    final repository = _EmptyPeopleTagsRepository();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    peopleTags = PeopleTagsCase(
      repository,
      realtime.case_,
      env: const Env(),
      logger: Logger('test'),
    );
    await peopleTags.load();
    GetIt.I
      ..registerSingleton<PeopleTagsRepositoryPort>(repository)
      ..registerSingleton<PeopleTagsCase>(peopleTags)
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
  });

  tearDown(() async {
    await GetIt.I.reset();
    await peopleTags.dispose();
    await realtimePort.dispose();
  });

  Future<RootRouter> pumpAt(WidgetTester tester, String path) async {
    final authCubit = _FakeAuthCubit();
    final settingsCubit = _FakeSettingsCubit();
    GetIt.I
      ..registerSingleton<AuthCubit>(authCubit)
      ..registerSingleton<SettingsCubit>(settingsCubit);
    final router = RootRouter(
      Logger('test'),
      authCubit,
      settingsCubit,
      PostJoinNavigationCubit(),
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) => DeepLink.path(path),
          includePrefixMatches: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('the people tags route is /settings/people-tags', (tester) async {
    expect(kPathPeopleTags, '/settings/people-tags');

    await pumpAt(tester, kPathPeopleTags);

    expect(find.byType(PeopleTagsScreen), findsOneWidget);
  });

  group('Settings entry', () {
    Future<_RecordingRouter> pumpSettings(
      WidgetTester tester, {
      required bool gate,
    }) async {
      final authCubit = _FakeAuthCubit();
      final settingsCubit = _FakeSettingsCubit();
      GetIt.I
        ..registerSingleton<AuthCubit>(authCubit)
        ..registerSingleton<SettingsCubit>(settingsCubit)
        ..registerSingleton<TrustPreferenceRepositoryPort>(
          _FakeTrustPreferences(),
        )
        ..registerSingleton<AttentionReconcilePort>(
          _FakeAttentionReconcile(),
        );
      final router = _RecordingRouter();
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
              child: TenturaResponsiveScope(
                child:
                    callWithPeopleTagsGate(SettingsScreen.new, gate: gate)
                        as Widget,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('a People tags tile opens the People tags screen', (
      tester,
    ) async {
      final router = await pumpSettings(tester, gate: true);

      final tile = find.byKey(const Key('settings.people_tags'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(router.pushed.map((r) => r.routeName), [PeopleTagsRoute.name]);
    });

    testWidgets('the tile is hidden while the feature is off', (tester) async {
      await pumpSettings(tester, gate: false);

      expect(find.byKey(const Key('settings.people_tags')), findsNothing);
    });
  });
}
