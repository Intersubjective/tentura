// A Requests card whose unread updates are Questions messages: tapping the
// card body must land in Questions (the same place as the update row), and
// the Questions updates must stay on the card until Questions is opened.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

const _viewerId = 'alice';
const _beaconId = 'request-1';

final class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: _viewerId, displayName: 'Alice'),
  );

  @override
  Stream<ProfileState> get stream =>
      Stream<ProfileState>.value(state).asBroadcastStream();
}

final class _NoDismissals implements OfferAcceptedDismissalPort {
  @override
  Future<Set<String>> load({required String viewerId}) async => {};

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async => {};
}

/// Records where the card sends the viewer.
class _TrackingRouter extends Mock implements StackRouter {
  final pushedRouteNames = <String>[];

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    pushedRouteNames.add(route.routeName);
    return null;
  }
}

AttentionReceipt _questionsMessage(String asker) => AttentionReceipt(
  id: 'question-$asker',
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: asker,
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/$_beaconId',
  createdAt: DateTime.utc(2026, 10, 29, 12),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: jsonEncode({
    'eventType': 'roomMessagePosted',
    'beaconId': _beaconId,
    'coordinationItemId': 'questions-1',
    'actorUserId': asker.toLowerCase(),
    'actorName': asker,
  }),
  surface: AttentionSurface.myWork,
  beaconId: _beaconId,
  actorUserId: asker.toLowerCase(),
  targetEntityId: 'message-$asker',
  destinationKind: 'beacon_room_message',
  coordinationItemId: 'questions-1',
);

AttentionReceipt _forwardNote() => AttentionReceipt(
  id: 'status-1',
  category: 'coordination',
  kind: 'coordinationChanged',
  priority: 'normal',
  title: 'Status changed',
  body: 'The Request moved on',
  actionUrl: '/#/beacon/view/$_beaconId',
  createdAt: DateTime.utc(2026, 10, 29, 12),
  collapsedCount: 1,
  presentationKey: 'request_status_changed',
  presentationPayloadJson: jsonEncode({'eventType': 'requestStatusChanged'}),
  surface: AttentionSurface.myWork,
  beaconId: _beaconId,
  destinationKind: 'beacon',
);

typedef _Desk = ({
  MyWorkCubit cubit,
  _TrackingRouter router,
  StubAttentionRepository attention,
});

Future<_Desk> _pumpCard(
  WidgetTester tester, {
  required AttentionReceipt newestUpdate,
}) async {
  final beacon = Beacon.empty.copyWith(
    id: _beaconId,
    title: 'Move the garden shed',
    updatedAt: DateTime(2026, 10, 28),
    status: BeaconStatus.open,
    author: const Profile(id: _viewerId, displayName: 'Alice'),
  );
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [beacon],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final attention = StubAttentionRepository()
    ..myWorkAttentionResult = [
      MyWorkBeaconAttention(
        beaconId: _beaconId,
        unseenCount: 2,
        latestUnseen: newestUpdate,
      ),
    ];
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(repo: repo, attentionRepository: attention),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);

  final router = _TrackingRouter();
  tester.view
    ..physicalSize = const Size(400, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
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
          child: RouterScope(
            controller: router,
            stateHash: 0,
            inheritableObserversBuilder: () => const [],
            child: StackRouterScope(
              controller: router,
              stateHash: 0,
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
    ),
  );
  await tester.pumpAndSettle();
  return (cubit: cubit, router: router, attention: attention);
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('questions-tap'));
    }
    if (!GetIt.I.isRegistered<BeaconRepository>()) {
      GetIt.I.registerSingleton<BeaconRepository>(FakeBeaconRepository());
    }
    if (!GetIt.I.isRegistered<ClosureRepository>()) {
      GetIt.I.registerSingleton<ClosureRepository>(ClosureRepositoryMock());
    }
    if (!GetIt.I.isRegistered<OfferAcceptedDismissals>()) {
      GetIt.I.registerSingleton<OfferAcceptedDismissals>(
        OfferAcceptedDismissals(_NoDismissals()),
      );
    }
  });

  tearDown(() {
    for (final unregister in <void Function()>[
      if (GetIt.I.isRegistered<BeaconRepository>())
        GetIt.I.unregister<BeaconRepository>,
      if (GetIt.I.isRegistered<ClosureRepository>())
        GetIt.I.unregister<ClosureRepository>,
      if (GetIt.I.isRegistered<OfferAcceptedDismissals>())
        GetIt.I.unregister<OfferAcceptedDismissals>,
    ]) {
      unregister();
    }
  });

  group('Requests card body tap with unread Questions updates', () {
    testWidgets('lands in Questions, not in the Request view', (tester) async {
      final desk = await _pumpCard(
        tester,
        newestUpdate: _questionsMessage('Bob'),
      );
      // The card shows the Questions update the tap is about.
      expect(find.byType(AttentionMiniCard), findsOneWidget);

      await tester.tap(find.text('Move the garden shed'));
      await tester.pumpAndSettle();

      expect(desk.router.pushedRouteNames, [BeaconLobbyRoute.name]);
    });

    testWidgets('keeps the Questions updates on the card after the tap', (
      tester,
    ) async {
      final desk = await _pumpCard(
        tester,
        newestUpdate: _questionsMessage('Bob'),
      );

      await tester.tap(find.text('Move the garden shed'));
      await tester.pumpAndSettle();

      // Only opening Questions clears them; going there is not that yet.
      final shown = desk.cubit.state.attentionByBeacon[_beaconId];
      expect(shown?.unseenCount, 2);
      expect(shown?.latestUnseen?.id, 'question-Bob');
      // Nothing was sent to the server to clear either, not even in the
      // background.
      expect(desk.attention.clearSnapshotCalls, isEmpty);
      expect(desk.attention.clearCalls, isEmpty);
      expect(find.byType(AttentionMiniCard), findsOneWidget);
    });

    testWidgets('guard: other updates still open the Request view', (
      tester,
    ) async {
      final desk = await _pumpCard(tester, newestUpdate: _forwardNote());
      expect(find.byType(AttentionMiniCard), findsOneWidget);

      await tester.tap(find.text('Move the garden shed'));
      await tester.pumpAndSettle();

      expect(desk.router.pushedRouteNames, [BeaconViewRoute.name]);
    });
  });
}
