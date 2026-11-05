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
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';
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

AttentionReceipt _questionsMessage() => AttentionReceipt(
  id: 'question-bob',
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: 'Bob',
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/$_beaconId',
  createdAt: DateTime.utc(2026, 10, 29, 12),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: jsonEncode({
    'eventType': 'roomMessagePosted',
    'beaconId': _beaconId,
    'coordinationItemId': 'questions-1',
  }),
  surface: AttentionSurface.myWork,
  beaconId: _beaconId,
  coordinationItemId: 'questions-1',
);

Future<({MyWorkCubit cubit, _TrackingRouter router})> _pumpAuthoredCard(
  WidgetTester tester, {
  required FakeRoomHints roomHints,
  Locale locale = const Locale('en'),
  bool phoneSurface = false,
}) async {
  if (phoneSurface) {
    await usePhoneSurface(tester);
  } else {
    tester.view
      ..physicalSize = const Size(400, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
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
        unseenCount: 1,
        latestUnseen: _questionsMessage(),
      ),
    ];
  final cubit = MyWorkCubit(
    userId: _viewerId,
    myWorkCase: buildTestMyWorkCase(
      repo: repo,
      attentionRepository: attention,
      roomHints: roomHints,
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.isSuccess && s.attentionLoaded);

  final router = _TrackingRouter();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
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
  return (cubit: cubit, router: router);
}

void main() {
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('issue-904'));
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

  group('#904 Request card unread counter and tap target', () {
    testWidgets('shows room unread count, not a Questions update row', (
      tester,
    ) async {
      final l10n = lookupL10n(const Locale('ru'));
      final hints = FakeRoomHints()
        ..hintsByBeaconId = {
          _beaconId: InboxRoomCardHints(
            isRoomMember: true,
            roomUnreadCount: 1,
            unreadRoom: 'questions',
            lastMessageText: 'Когда удобно привезти грунт?',
            lastMessageAuthorName: 'Bob',
            lastMessageAuthorId: 'bob',
            lastMessageAt: DateTime.utc(2026, 10, 29, 11, 30),
          ),
        };
      await _pumpAuthoredCard(
        tester,
        roomHints: hints,
        locale: const Locale('ru'),
        phoneSurface: true,
      );

      expect(find.byType(AttentionMiniCard), findsNothing);
      expect(find.text(l10n.myWorkUnreadCount(1)), findsOneWidget);
      expect(find.textContaining('Новое сообщение в вопросах'), findsNothing);
    });

    testWidgets('card tap opens Questions when unreadRoom is questions', (
      tester,
    ) async {
      final hints = FakeRoomHints()
        ..hintsByBeaconId = {
          _beaconId: const InboxRoomCardHints(
            isRoomMember: true,
            roomUnreadCount: 1,
            unreadRoom: 'questions',
          ),
        };
      final desk = await _pumpAuthoredCard(tester, roomHints: hints);

      await tester.tap(find.text('Move the garden shed'));
      await tester.pumpAndSettle();

      expect(desk.router.pushedRouteNames, [BeaconLobbyRoute.name]);
    });

    testWidgets(
      'card tap opens the Request view when unreadRoom is discussion',
      (
        tester,
      ) async {
        final hints = FakeRoomHints()
          ..hintsByBeaconId = {
            _beaconId: const InboxRoomCardHints(
              isRoomMember: true,
              roomUnreadCount: 2,
              unreadRoom: 'discussion',
            ),
          };
        final desk = await _pumpAuthoredCard(tester, roomHints: hints);

        await tester.tap(find.text('Move the garden shed'));
        await tester.pumpAndSettle();

        expect(desk.router.pushedRouteNames, [BeaconViewRoute.name]);
      },
    );
  });

  test(
    'InboxRoomContextBatch maps unreadRoom through the repository',
    () async {
      final sent = <WireSent>[];
      await withRemoteWire(
        {
          'InboxRoomContextBatch': {
            'InboxRoomContextBatch': [
              {
                '__typename': 'v2_InboxRoomContextRow',
                'beaconId': _beaconId,
                'isRoomMember': true,
                'roomUnreadCount': 1,
                'unreadRoom': 'questions',
                'postRootExcerpt': null,
                'currentLine': null,
                'lastRoomMeaningfulChange': null,
                'nextMoveText': null,
                'lastSeenAt': null,
                'openBlockerTitle': null,
                'openBlockerCreatorId': null,
                'openBlockerTargetPersonId': null,
                'openBlockerResponsibleUserId': null,
                'openBlockerCreatedAt': null,
                'openBlockerCreatorDisplayName': null,
                'openBlockerCreatorImageId': null,
                'openBlockerCreatorHasPicture': null,
                'publicFactSnippet': null,
                'planSliceJson': null,
                'lastActivityAt': null,
                'lastMessageAt': '2030-01-01T12:00:00.000Z',
                'lastMessageText': 'Hello?',
                'lastMessageAuthorId': 'bob',
                'lastMessageAuthorName': 'Bob',
                'lastMessageKind': null,
                'parentBeaconId': null,
                'parentTitle': null,
              },
            ],
          },
        },
        sent,
        (remote) async {
          final repo = BeaconRoomHintsRepository(remote);
          final map = await repo.fetchByBeaconIds([_beaconId]);
          final hint = map[_beaconId];
          expect(hint?.roomUnreadCount, 1);
          expect(hint?.unreadRoom, 'questions');
        },
      );
      expect(sent.single.operationName, 'InboxRoomContextBatch');
    },
  );
}
