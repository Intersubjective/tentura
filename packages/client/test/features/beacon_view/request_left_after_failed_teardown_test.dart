// #745 (Sentry TENTURA-CLIENT-4D): ProviderNotFound for ThreadHostCubit,
// thrown from the Request scope's status listener while the viewer was on
// Inbox, minutes after leaving the Request.
//
// Both production sessions (traces 9ef8bb80…, tentura@7.44.1, and e520dc33…,
// tentura@7.54.0) first hit TENTURA-CLIENT-42 at the moment they left a
// Request: a null check in SelectionContainer.dispose, "thrown while
// finalizing the widget tree" (#761, fixed in 7.59.51). Flutter clears its
// list of removed elements before unmounting them, so one failing dispose
// leaves every ancestor of the failing widget in the removed Request
// deactivated but never unmounted: BeaconViewScope's providers stay alive,
// the Request cubit keeps loading, and its listener keeps its subscription.
// When the next state arrives, the listener reads ThreadHostCubit from a
// deactivated context, which has no providers any more.
//
// The selection failure itself only exists in web release builds (#761 has
// its own tests); here a widget under the real Request route fails its
// dispose the same way, and the route's own load lands afterwards, through
// the production Ferry chain and the real BeaconViewScope.

import 'dart:async';

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

/// Fails its teardown, as SelectionContainer.dispose did in #761.
class _FailsOnDispose extends StatefulWidget {
  const _FailsOnDispose();

  @override
  State<_FailsOnDispose> createState() => _FailsOnDisposeState();
}

class _FailsOnDisposeState extends State<_FailsOnDispose> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {
    super.dispose();
    throw StateError('teardown failed');
  }
}

const _awayRoute = 'InboxStandInRoute';

/// The Request route as the app nests it, plus somewhere to go instead.
class _LeaveRequestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      usesPathAsKey: true,
      page: BeaconViewRoute.page,
      path: '$kPathBeaconView/:id',
      children: [
        AutoRoute(
          page: PageInfo(
            BeaconViewOperationalRoute.name,
            builder: (data) => Stack(
              children: [
                BeaconViewOperationalRoute.page.builder(data),
                // After the screen, so the screen itself still unmounts and
                // only the route and scope above it stay behind.
                const _FailsOnDispose(),
              ],
            ),
          ),
          path: '',
          initial: true,
        ),
      ],
    ),
    AutoRoute(
      page: PageInfo(_awayRoute, builder: (_) => const Text('inbox')),
      path: '/home/inbox',
    ),
  ];
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'timed out waiting');
}

void main() {
  testWidgets(
    'a Request left while loading, whose teardown failed, finishes loading '
    'without looking up its providers',
    (tester) async {
      final server = openRoundsServer(
        viewerId: kOpenRoundsAuthorId,
        status: BeaconStatus.open,
      );
      final effects = FakeUiEffectPort();
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await http.runWithClient(() async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        final realtime = buildTestRealtimeSync();
        final router = _LeaveRequestRouter();
        final leaked = <BlocBase<Object?>>[];
        await GetIt.I.reset();
        try {
          await remote.setSessionAuth();
          final wired = buildWiredBeaconViewCase(remote, realtime);
          final images = ImageRepository();
          final profile = _SignedInProfileCubit(
            const Profile(id: kOpenRoundsAuthorId, displayName: 'Viewer'),
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
                logger: Logger('request-left-teardown'),
              ),
            )
            ..registerSingleton<AuthorInviteCase>(
              AuthorInviteCase(
                AuthorInviteRepository(remote),
                env: const Env(),
                logger: Logger('request-left-teardown'),
              ),
            );
          await tester.pumpWidget(
            MaterialApp.router(
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              locale: const Locale('en'),
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

          // Round 1, the kind gate, answers; the Request scope mounts and
          // asks for the Request.
          await _pumpUntil(tester, () => server.calls.isNotEmpty);
          server.answerPending();
          await _pumpUntil(
            tester,
            () => find.byType(BeaconViewScreen).evaluate().isNotEmpty,
          );
          final cubit = tester
              .element(find.byType(BeaconViewScreen))
              .read<BeaconViewCubit>();
          // Never closed once the teardown fails; closed by hand below.
          leaked.add(cubit);
          expect(cubit.state.beaconContentLoaded, isFalse);

          // The viewer goes to Inbox before the Request loads, and the
          // Request's teardown fails.
          unawaited(router.replaceAll([const PageRouteInfo(_awayRoute)]));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('inbox'), findsOneWidget);
          expect(tester.takeException(), isStateError);

          // The Request's own reads land afterwards.
          await server.drain(
            wait: () => tester.pump(const Duration(milliseconds: 10)),
          );
          await tester.pump();

          expect(
            cubit.state.beaconContentLoaded,
            isTrue,
            reason: 'the load reached the stale scope\n${server.describe()}',
          );
          expect(tester.takeException(), isNull);
        } finally {
          // Closing awaits work that only fake time moves on.
          for (final bloc in leaked) {
            unawaited(bloc.close());
          }
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
          await realtime.port.dispose();
          await remote.close();
          await GetIt.I.reset();
        }
      }, () => server.client);
    },
  );
}
