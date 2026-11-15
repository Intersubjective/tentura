// Removing a brought fact (✕ on the copy editor) must rewrite the route's
// `fork_facts` query in place, so a web reload before the first autosave does
// not bring the removed fact back. The URL is read from the router's
// currentUrl and round-tripped through a fresh app, never parsed by format
// beyond its query values.

import 'dart:async';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';
import 'fork_beacon_ports.dart';

final _source = Beacon.empty.copyWith(
  id: 'Bsource00001',
  title: 'Fix the north fence',
  description: 'Posts are loose near the gate.',
  status: BeaconStatus.open,
);

late ForkingBeaconWritePort _write;

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

/// The production create page at its production path, under a stub home.
class _TestRouter extends RootStackRouter {
  _TestRouter({required this.home});

  final String home;

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo('Home', builder: (_) => Text(home)),
      path: '/',
      initial: true,
    ),
    AutoRoute(page: BeaconCreateRoute.page, path: kPathBeaconNew),
  ];
}

void main() {
  setUp(_registerCollaborators);

  tearDown(GetIt.I.reset);

  Future<_TestRouter> pumpRouter(
    WidgetTester tester, {
    String? deepLink,
  }) async {
    final router = _TestRouter(home: 'home');
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        builder: (_, child) => TenturaResponsiveScope(child: child!),
        routerConfig: router.config(
          deepLinkBuilder: deepLink == null
              ? null
              : (_) => DeepLink.path(deepLink),
        ),
      ),
    );
    await settle(tester);
    return router;
  }

  /// The cubit the create page built for the open editor.
  BeaconCreateCubit openCubit(WidgetTester tester) =>
      tester.element(find.byType(BeaconCreateScreen)).read<BeaconCreateCubit>();

  List<String> stateFactIds(BeaconCreateCubit cubit) => cubit.state.forkFactIds;

  /// Opens the editor the way «Create from this Request» does.
  Future<void> openCopy(
    WidgetTester tester,
    _TestRouter router, {
    List<String>? forkFactIds,
    String initialTab = '',
    String draftId = '',
  }) async {
    final route =
        Function.apply(BeaconCreateRoute.new, const [], {
              #forkSourceId: _source.id,
              #initialTab: initialTab,
              #draftId: draftId,
              #forkFactIds: ?forkFactIds,
            })
            as BeaconCreateRoute;
    unawaited(router.push(route));
    await settle(tester);
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
  }

  List<String> urlFactIds(_TestRouter router) =>
      Uri.parse(router.currentUrl).queryParametersAll['fork_facts'] ?? [];

  group('removing a brought fact rewrites the editor URL', () {
    testWidgets('the route query lists only the remaining fact ids', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router, forkFactIds: const ['Fkey', 'Fshed']);

      await openCubit(tester).removeBroughtFact('Fkey');
      await settle(tester);

      expect(urlFactIds(router), ['Fshed']);
    });

    testWidgets('a reload after removal restores only the remaining facts', (
      tester,
    ) async {
      final first = await pumpRouter(tester);
      await openCopy(tester, first, forkFactIds: const ['Fkey', 'Fshed']);
      await openCubit(tester).removeBroughtFact('Fkey');
      await settle(tester);
      final url = first.currentUrl;
      // The reload must restore from the URL alone, not from an autosave.
      expect(_write.forkCalls, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await GetIt.I.reset();
      _registerCollaborators();
      await pumpRouter(tester, deepLink: url);

      final cubit = openCubit(tester);
      expect(stateFactIds(cubit), ['Fshed']);
      expect(
        cubit.state.broughtFacts.map((f) => f.id),
        isNot(contains('Fkey')),
      );
    });

    testWidgets('removing every fact drops fork_facts from the URL', (
      tester,
    ) async {
      final first = await pumpRouter(tester);
      await openCopy(tester, first, forkFactIds: const ['Fkey', 'Fshed']);
      final cubit = openCubit(tester);
      await cubit.removeBroughtFact('Fkey');
      await cubit.removeBroughtFact('Fshed');
      await settle(tester);

      expect(
        Uri.parse(
          first.currentUrl,
        ).queryParametersAll.containsKey('fork_facts'),
        isFalse,
      );
      final url = first.currentUrl;

      await tester.pumpWidget(const SizedBox());
      await GetIt.I.reset();
      _registerCollaborators();
      await pumpRouter(tester, deepLink: url);
      expect(stateFactIds(openCubit(tester)), isEmpty);
    });

    testWidgets('other query parameters and the path are unchanged', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router, forkFactIds: const ['Fkey', 'Fshed']);
      final before = Uri.parse(router.currentUrl);

      await openCubit(tester).removeBroughtFact('Fkey');
      await settle(tester);
      final after = Uri.parse(router.currentUrl);

      expect(after.path, before.path);
      expect(after.path, startsWith(kPathBeaconNew));
      Map<String, List<String>> others(Uri u) => {
        for (final e in u.queryParametersAll.entries)
          if (e.key != 'fork_facts') e.key: e.value,
      };
      expect(others(after), others(before));
      expect(
        after.queryParametersAll.containsKey('fork_facts'),
        isTrue,
        reason: 'the rewrite must happen, not just keep the old url',
      );
      expect(urlFactIds(router), ['Fshed']);
    });

    testWidgets('the rewrite replaces the history entry', (tester) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router, forkFactIds: const ['Fkey', 'Fshed']);
      final depth = router.stack.length;
      final reports = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          if (call.method == 'routeInformationUpdated') {
            reports.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );

      await openCubit(tester).removeBroughtFact('Fkey');
      await settle(tester);

      expect(urlFactIds(router), ['Fshed']);
      expect(router.stack.length, depth);
      expect(find.byType(BeaconCreateScreen), findsOneWidget);
      expect(reports, isNotEmpty, reason: 'the browser URL must be updated');
      expect(
        reports.every((r) => r['replace'] == true),
        isTrue,
        reason: 'no new browser history entry may be pushed: $reports',
      );
    });

    testWidgets('remaining ids keep their order as separate values', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      await openCopy(
        tester,
        router,
        forkFactIds: const ['Fa', 'Fb', 'Fc'],
      );

      await openCubit(tester).removeBroughtFact('Fb');
      await settle(tester);

      expect(urlFactIds(router), ['Fa', 'Fc']);
      expect(stateFactIds(openCubit(tester)), ['Fa', 'Fc']);
    });

    testWidgets('tab and draft id survive the removal', (tester) async {
      final router = await pumpRouter(tester);
      await openCopy(
        tester,
        router,
        forkFactIds: const ['Fkey', 'Fshed'],
        initialTab: 'plan',
        draftId: 'Ddraft000001',
      );
      final before = Uri.parse(router.currentUrl).queryParameters;
      expect(before['tab'], 'plan');
      expect(before['draft_id'], 'Ddraft000001');
      expect(before['fork_from'], _source.id);

      await openCubit(tester).removeBroughtFact('Fkey');
      await settle(tester);

      final after = Uri.parse(router.currentUrl);
      expect(urlFactIds(router), ['Fshed']);
      expect(after.queryParameters['tab'], 'plan');
      expect(after.queryParameters['draft_id'], 'Ddraft000001');
      expect(after.queryParameters['fork_from'], _source.id);
    });

    testWidgets('removing an id that is not listed changes nothing', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router, forkFactIds: const ['Fkey', 'Fshed']);
      final cubit = openCubit(tester);

      await cubit.removeBroughtFact('Fother');
      await settle(tester);

      expect(stateFactIds(cubit), ['Fkey', 'Fshed']);
      expect(urlFactIds(router), ['Fkey', 'Fshed']);
    });
  });
}

/// Bounded pumps: the editor keeps timers (autosave) that never settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The editor's GetIt collaborators (registered again after a reload).
void _registerCollaborators() {
  _write = ForkingBeaconWritePort(source: _source);
  GetIt.I
    ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
    ..registerSingleton<BeaconCreateCase>(
      fakeBeaconCreateCase(write: _write),
    );
}
