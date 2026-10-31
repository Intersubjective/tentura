// The Request route (BeaconViewRoute) as navigation opens it on a cold deep
// link: the kind gate, BeaconViewScope with all its cubits (Request,
// hierarchy, threads, room host, plan) and BeaconViewScreen, every read going
// through the production cases, repositories, Ferry link chain and
// RemoteApiService. Only HTTP is faked, by a server that answers from
// schema.graphql and holds responses back in rounds (GraphqlRoundTripServer),
// so the test counts every GraphQL request the route sends on open and the
// longest chain of requests that wait on each other (Sentry "Consecutive
// HTTP" on BeaconViewRoute).
//
// Before the fix (measured with this harness, 1280×900 and 390×844 alike):
//   author, live Request:         18 requests, 4 round trips
//   author, wrapping-up Request:  16 requests, 5 round trips
//   helper, wrapping-up Request:  16 requests, 5 round trips
//   helper, live Request:         14 requests, 3 round trips (already minimal)
// After (forwards and the final check join the access round and do not
// re-read the Request; helper live was already at this floor):
//   author, live Request:         17 requests, 3 round trips
//   author, wrapping-up Request:  15 requests, 3 round trips
//   helper, wrapping-up Request:  15 requests, 3 round trips
//   helper, live Request:         14 requests, 3 round trips
// Since then the "Seen by" lookup (#766) joins the Request's own round: one
// more request in every case (18 / 16 / 16 / 15), no more round trips.
// Helper live at 390×844 sends that same chain; the frame overflows a
// helper-only row there, so the pin is the 1280×900 open.
// Round 1 is the kind gate (Request or Post?), round 2 the Request itself
// with the threads and parent reads, round 3 everything that needs the
// Request's access, including forwards and the final check.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/author_invite_repository.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon_plan/data/repository/beacon_plan_repository.dart';
import 'package:tentura/features/beacon_plan/domain/use_case/beacon_plan_case.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/post_view/data/repository/beacon_kind_repository.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart'
    show InMemoryBeaconChildCommandStore;
import '../../support/graphql_round_trip_server.dart';
import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'request_open_round_trips_support.dart';

class _SignedInProfileCubit extends Mock implements ProfileCubit {
  _SignedInProfileCubit(this._profile);

  final Profile _profile;

  @override
  ProfileState get state => ProfileState(profile: _profile);

  @override
  Stream<ProfileState> get stream => Stream.value(state);
}

class _RequestRouteRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
      children: [
        AutoRoute(
          page: BeaconViewOperationalRoute.page,
          path: '',
          initial: true,
        ),
      ],
    ),
  ];
}

/// What the user sees once the route settled, plus how it got there.
typedef _OpenedRoute = ({
  GraphqlRoundTripServer server,
  BeaconViewState state,
  FakeUiEffectPort effects,
  bool titleShown,
});

/// Navigates straight to the Request (a cold deep link: nothing cached) as
/// [viewerId] and answers every read until the route stops sending any.
Future<_OpenedRoute> _openRoute(
  WidgetTester tester, {
  required String viewerId,
  required BeaconStatus status,
  Size size = const Size(1280, 900),
}) async {
  final server = openRoundsServer(viewerId: viewerId, status: status);
  final effects = FakeUiEffectPort();
  late _OpenedRoute opened;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await http.runWithClient(() async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    final realtime = buildTestRealtimeSync();
    final router = _RequestRouteRouter();
    await GetIt.I.reset();
    try {
      await remote.setSessionAuth();
      final wired = buildWiredBeaconViewCase(remote, realtime);
      final images = ImageRepository();
      final profile = _SignedInProfileCubit(
        Profile(id: viewerId, displayName: 'Viewer'),
      );
      final screen = ScreenCubit(effects);
      GetIt.I
        ..registerSingleton<UiEffectPort>(effects)
        ..registerSingleton<ProfileCubit>(profile)
        ..registerSingleton<ScreenCubit>(screen)
        ..registerSingleton<ImageRepository>(images)
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        )
        ..registerSingleton<BeaconKindRepository>(
          BeaconKindRepository(remote),
        )
        ..registerSingleton<BeaconViewCase>(wired.viewCase)
        ..registerSingleton<BeaconThreadsCase>(wired.threadsCase)
        ..registerSingleton<BeaconHierarchyCase>(
          BeaconHierarchyCase(
            BeaconHierarchyRepository(remote),
            BeaconCreateCase(wired.beacons, images),
            wired.beacons,
            InMemoryBeaconChildCommandStore(),
            realtime.case_,
          ),
        )
        ..registerSingleton<BeaconPlanCase>(
          BeaconPlanCase(
            BeaconPlanRepository(remote, realtime.port),
            env: const Env(),
            logger: Logger('request-route-rounds'),
          ),
        )
        ..registerSingleton<AuthorInviteCase>(
          AuthorInviteCase(
            AuthorInviteRepository(remote),
            env: const Env(),
            logger: Logger('request-route-rounds'),
          ),
        );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          // The app root's providers (App.builder) that the route reads.
          builder: (context, child) => MultiBlocProvider(
            providers: [
              BlocProvider<ScreenCubit>.value(value: screen),
              BlocProvider<ProfileCubit>.value(value: profile),
            ],
            child: child!,
          ),
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink.path(
              '$kPathBeaconView/$kOpenRoundsBeaconId',
            ),
          ),
        ),
      );
      await server.drain(
        wait: () => tester.pump(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final cubit = tester
          .element(find.byType(BeaconViewScreen))
          .read<BeaconViewCubit>();
      opened = (
        server: server,
        state: cubit.state,
        effects: effects,
        titleShown: find.textContaining(kOpenRoundsTitle).evaluate().isNotEmpty,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await realtime.port.dispose();
      await remote.close();
      await GetIt.I.reset();
    }
  }, () => server.client);
  return opened;
}

void _expectShown(_OpenedRoute opened, WidgetTester tester) {
  final trace = opened.server.describe();
  expect(tester.takeException(), isNull, reason: trace);
  expect(opened.effects.emitted, isEmpty, reason: trace);
  expect(opened.titleShown, isTrue, reason: trace);
  expect(opened.state.loadError, isNull, reason: trace);
  expect(opened.state.beaconContextLoaded, isTrue, reason: trace);
  expect(opened.state.firstLoadDone, isTrue, reason: trace);
  expect(opened.state.displayStatus?.canCancel, isTrue, reason: trace);
}

void main() {
  group('Opening the Request route on a cold link', () {
    for (final (label, size) in [
      ('wide', const Size(1280, 900)),
      ('phone', const Size(390, 844)),
    ]) {
      testWidgets(
        'the author of a live Request sees it with their forward status in '
        'at most three round trips and fewer than 19 requests ($label)',
        (tester) async {
          final opened = await _openRoute(
            tester,
            viewerId: kOpenRoundsAuthorId,
            status: BeaconStatus.open,
            size: size,
          );
          final server = opened.server;
          final trace = server.describe();

          _expectShown(opened, tester);
          expect(opened.state.forwardsLoaded, isTrue, reason: trace);
          expect(
            opened.state.myForwards.map((edge) => edge.id),
            [kOpenRoundsForwardId],
            reason: trace,
          );

          expectOpenRounds(
            server,
            rounds: 3,
            calls: 18,
            roundsBefore: 4,
            callsBefore: 18,
          );
        },
      );
    }

    for (final (who, viewerId) in [
      ('the author of', kOpenRoundsAuthorId),
      ('a helper on', kOpenRoundsHelperId),
    ]) {
      testWidgets(
        '$who a wrapping-up Request sees the final check in at most '
        'three round trips and fewer than 17 requests',
        (tester) async {
          final opened = await _openRoute(
            tester,
            viewerId: viewerId,
            status: BeaconStatus.reviewOpen,
          );
          final server = opened.server;
          final trace = server.describe();

          _expectShown(opened, tester);
          expect(opened.state.closureState?.epoch, 2, reason: trace);
          expect(
            opened.state.closureState?.canCloseNow,
            viewerId == kOpenRoundsAuthorId,
            reason: trace,
          );

          expectOpenRounds(
            server,
            rounds: 3,
            calls: 16,
            roundsBefore: 5,
            callsBefore: 16,
          );
        },
      );
    }

    testWidgets(
      'a helper on a live Request sees it in three round trips and 15 requests',
      (tester) async {
        final opened = await _openRoute(
          tester,
          viewerId: kOpenRoundsHelperId,
          status: BeaconStatus.open,
        );
        final server = opened.server;
        final trace = server.describe();

        _expectShown(opened, tester);
        expect(opened.state.isBeaconMine, isFalse, reason: trace);
        expectOpenRounds(
          server,
          rounds: 3,
          calls: 15,
          roundsBefore: 3,
          callsBefore: 14,
        );
      },
    );
  });
}
