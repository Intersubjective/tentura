// #597 (owner decision D2, option A): after offering help, the helper's
// Requests-tab card shows a visible Forward action, like the author's card,
// whenever the viewer may forward the Request. The overflow menu entry stays.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_fetch_types.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

const _viewerId = 'helper-1';
const _beaconId = 'open-597';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

class _RecordingRouter extends Mock implements StackRouter {
  final pushes = <PageRouteInfo>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushes.add(route);
    return null;
  }
}

MyWorkHelpOfferedRow _row({required bool viewerCanForward}) => (
  beacon: Beacon.empty.copyWith(
    id: _beaconId,
    title: 'Open request',
    updatedAt: DateTime(2026, 9, 5),
    status: BeaconStatus.open,
    viewerCanForward: viewerCanForward,
    author: const Profile(id: 'auth', displayName: 'Author Co'),
  ),
  offerHelpMessage: 'I can help',
  helpType: null,
  authorResponseType: null,
  stakeState: CommitmentStakeState.none,
  forwarderSenders: const <Profile>[],
  helpOfferRowUpdatedAt: DateTime(2026, 9, 4),
  authorCoordinationUpdatedAt: null,
  coordinationAuthor: null,
);

Future<_RecordingRouter> _pump(
  WidgetTester tester, {
  required bool viewerCanForward,
}) async {
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: const <Beacon>[],
      helpOfferedNonArchived: [_row(viewerCanForward: viewerCanForward)],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess);

  tester.view
    ..physicalSize = const Size(360, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = _RecordingRouter();
  await tester.pumpWidget(
    StackRouterScope(
      controller: router,
      stateHash: 0,
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: MultiBlocProvider(
            providers: [
              BlocProvider<MyWorkCubit>.value(value: cubit),
              BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
            ],
            child: Scaffold(
              body: BlocBuilder<MyWorkCubit, MyWorkState>(
                builder: (context, state) => ListView(
                  children: [
                    for (final vm in state.nonArchivedCards)
                      MyWorkCardRouter(vm: vm),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(
    cubit.state.nonArchivedCards.single.kind,
    MyWorkCardKind.helpOfferedActive,
  );
  return router;
}

final _forwardCta = find.widgetWithText(TenturaTextAction, 'Forward');

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('my-work-helper-forward'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
  });

  tearDown(() {
    for (final unregister in <void Function()>[
      if (GetIt.I.isRegistered<BeaconRepository>())
        GetIt.I.unregister<BeaconRepository>,
      if (GetIt.I.isRegistered<ClosureRepository>())
        GetIt.I.unregister<ClosureRepository>,
    ]) {
      unregister();
    }
  });

  testWidgets('helper card shows a visible Forward when the viewer can '
      'forward; tapping it opens the forward screen', (tester) async {
    final router = await _pump(tester, viewerCanForward: true);

    expect(_forwardCta, findsOneWidget);

    await tester.tap(_forwardCta);
    await tester.pump();

    final route = router.pushes.single;
    expect(route, isA<ForwardBeaconRoute>());
    expect((route as ForwardBeaconRoute).args!.beaconId, _beaconId);
  });

  testWidgets('helper card has no Forward when the viewer cannot forward', (
    tester,
  ) async {
    final router = await _pump(tester, viewerCanForward: false);

    expect(_forwardCta, findsNothing);
    expect(router.pushes, isEmpty);
  });

  testWidgets('open helper card keeps its Archive action beside Forward', (
    tester,
  ) async {
    await _pump(tester, viewerCanForward: true);

    expect(find.widgetWithText(TenturaTextAction, 'Archive'), findsOneWidget);
  });
}
