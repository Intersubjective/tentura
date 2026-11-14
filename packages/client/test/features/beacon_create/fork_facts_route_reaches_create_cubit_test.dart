// «Create from this Request» opens the editor at `/beacon/new` with the
// source in `fork_from` and the facts ticked on the fork sheet in
// `fork_facts` (fact continuity plan §6.4). The production BeaconCreateRoute
// page builds the screen and, through `BeaconCreateScreen.wrappedRoute`, the
// BeaconCreateCubit; the ticked ids must land in that cubit's state, both on
// the first open and after a web reload, which rebuilds the route from its
// URL alone. The URL encoding is the router's business and is never read
// here: the reload test only round-trips the URL the router itself wrote.
//
// `forkFactIds` does not exist yet on the route or the cubit state, so both
// are reached through `Function.apply` / `dynamic`: each test fails on its
// own instead of the file failing to compile.

import 'dart:async';

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

  Future<_TestRouter> pumpRouter(WidgetTester tester, {String? deepLink}) async {
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

  List<String> stateFactIds(BeaconCreateCubit cubit) =>
      ((cubit.state as dynamic).forkFactIds as List).cast<String>();

  /// Opens the editor the way «Create from this Request» does.
  Future<void> openCopy(
    WidgetTester tester,
    _TestRouter router, {
    List<String>? forkFactIds,
  }) async {
    final route =
        Function.apply(BeaconCreateRoute.new, const [], {
              #forkSourceId: _source.id,
              #forkFactIds: ?forkFactIds,
            })
            as BeaconCreateRoute;
    unawaited(router.push(route));
    await settle(tester);
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
  }

  group('facts ticked on the fork sheet reach the copy editor', () {
    testWidgets('the create page opened with fork_facts holds exactly those '
        'ids in its cubit state', (tester) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router, forkFactIds: const ['Fkey', 'Fshed']);

      expect(stateFactIds(openCubit(tester)), ['Fkey', 'Fshed']);
    });

    testWidgets('a reload of the editor URL keeps the same fact ids', (
      tester,
    ) async {
      final first = await pumpRouter(tester);
      await openCopy(tester, first, forkFactIds: const ['Fkey', 'Fshed']);
      final url = first.currentUrl;
      expect(url, startsWith(kPathBeaconNew));

      // A fresh app at that URL: the route args come from the query alone.
      await tester.pumpWidget(const SizedBox());
      await GetIt.I.reset();
      _registerCollaborators();
      await pumpRouter(tester, deepLink: url);

      expect(find.byType(BeaconCreateScreen), findsOneWidget);
      expect(stateFactIds(openCubit(tester)), ['Fkey', 'Fshed']);
    });

    testWidgets('the create page opened without fork_facts holds no fact ids', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      await openCopy(tester, router);

      expect(stateFactIds(openCubit(tester)), isEmpty);
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
  GetIt.I
    ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
    ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
    ..registerSingleton<AuthCase>(
      buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
    )
    ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
    ..registerSingleton<BeaconCreateCase>(
      fakeBeaconCreateCase(write: ForkingBeaconWritePort(source: _source)),
    );
}
