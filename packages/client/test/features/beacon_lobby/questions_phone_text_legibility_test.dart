import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/mock/client_repository_mocks.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/attention/offer_accepted_dismissals.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_chat.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_unread_divider.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_cards.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import '../../support/test_realtime_sync.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit;
import '../my_work/my_work_test_support.dart' hide FakeBeaconThreadsRepository;
import 'fake_lobby_port.dart';

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
  createdAt: _now,
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

typedef _Desk = ({
  MyWorkCubit cubit,
  _TrackingRouter router,
  StubAttentionRepository attention,
});

Future<_Desk> _pumpCard(
  WidgetTester tester, {
  required AttentionReceipt newestUpdate,
  required Locale locale,
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
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
                  builder: (context, state) => SafeArea(
                    minimum: EdgeInsets.symmetric(
                      horizontal: context.tt.screenHPadding,
                    ),
                    child: ListView(
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
    ),
  );
  await tester.pumpAndSettle();
  return (cubit: cubit, router: router, attention: attention);
}

final _now = DateTime(2026, 10, 30, 12);

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void _expectInside(Rect bounds, Rect container, String reason) {
  // Permit only floating-point layout noise, not a clipped logical pixel.
  final allowed = container.inflate(0.01);
  expect(bounds.left, greaterThanOrEqualTo(allowed.left), reason: reason);
  expect(bounds.right, lessThanOrEqualTo(allowed.right), reason: reason);
  expect(bounds.top, greaterThanOrEqualTo(allowed.top), reason: reason);
  expect(bounds.bottom, lessThanOrEqualTo(allowed.bottom), reason: reason);
}

void _expectNoAncestorClipping(RenderBox content, String label) {
  RenderObject child = content;
  while (child.parent != null) {
    final parent = child.parent!;
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      // Clips are in the parent's coordinates. Transform the original text
      // bounds into each ancestor's coordinates, including scroll offsets.
      final bounds = MatrixUtils.transformRect(
        content.getTransformTo(parent),
        Offset.zero & content.size,
      );
      _expectInside(
        bounds,
        clip,
        '$label must not be clipped by ${parent.runtimeType}',
      );
    }
    child = parent;
  }
}

void _expectFullyVisible(
  WidgetTester tester,
  Finder text,
  String label, {
  required Finder within,
}) {
  expect(text, findsOneWidget, reason: '$label must be present');
  final richText = find.descendant(of: text, matching: find.byType(RichText));
  expect(richText, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '$label must be painted in full, without an ellipsis',
  );
  final bounds = tester.getRect(richText);
  expect(bounds.left, greaterThanOrEqualTo(0), reason: label);
  expect(bounds.right, lessThanOrEqualTo(375), reason: label);
  expect(bounds.top, greaterThanOrEqualTo(0), reason: label);
  expect(bounds.bottom, lessThanOrEqualTo(667), reason: label);
  expect(within, findsOneWidget);
  _expectInside(
    bounds,
    tester.getRect(within),
    '$label must stay inside its visible row',
  );
  _expectNoAncestorClipping(paragraph, label);
}

class _UnreadQuestionsPort extends FakeLobbyPort {
  _UnreadQuestionsPort() : super(viewerId: _viewerId, authorId: _viewerId);

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async =>
      (await super.access(beaconId)).copyWith(messageCount: 3, unreadCount: 3);
}

Future<void> _pumpQuestionsChat(WidgetTester tester, Locale locale) async {
  final getIt = GetIt.I;
  const peer = Profile(id: 'bob', displayName: 'Bob R7');
  final server = FakeBeaconThreadsRepository(userId: _viewerId)
    ..messages = [
      for (var i = 1; i <= 3; i++)
        RoomMessage(
          id: 'question-$i',
          beaconId: _beaconId,
          threadItemId: 'Llobby',
          authorId: peer.id,
          author: peer,
          body: 'Question $i',
          createdAt: _now.add(Duration(minutes: i)),
        ),
    ];
  addTearDown(server.dispose);
  final sync = buildTestRealtimeSync();
  addTearDown(sync.port.dispose);
  final watermarks = RoomReadWatermarkStore.testing();
  addTearDown(watermarks.dispose);
  watermarks.confirmSynced(_beaconId, _now, threadId: 'Llobby');
  final roomCase = roomCubitMakeCase(
    server,
    watermarkStore: watermarks,
    realtimeSyncCase: sync.case_,
  );
  final effects = RecordingEffects();
  final profile = _TestProfileCubit();
  final presence = RoomBodyHarnessPresenceCubit();
  final presenceRepository = roomCubitFakePresenceRepository();
  final lobbySync = FakeRealtimeSyncPort();
  addTearDown(lobbySync.dispose);
  final lobbyCase = lobbyCaseFor(
    _UnreadQuestionsPort(),
    lobbySync,
  );
  final attention = buildStubAttentionCase();
  addTearDown(attention.dispose);
  getIt
    ..registerSingleton<ProfileCubit>(profile)
    ..registerSingleton<PresenceCubit>(presence)
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<AttentionCase>(attention)
    ..registerSingleton<BeaconLobbyCase>(lobbyCase)
    ..registerSingleton<RoomReadWatermarkStore>(watermarks)
    ..registerSingleton<BeaconThreadsCase>(roomCase)
    ..registerSingleton<BeaconFactCardRepository>(
      FakeBeaconFactCardRepository(),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(presenceRepository)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());
  final lobby = BeaconLobbyCubit(
    lobbyCase,
    effects,
    beaconId: _beaconId,
    attention: attention,
  );
  addTearDown(lobby.close);
  await lobby.load();
  tester.view
    ..physicalSize = const Size(375, 667)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profile),
        BlocProvider<PresenceCubit>.value(value: presence),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
        BlocProvider<BeaconLobbyCubit>.value(value: lobby),
      ],
      child: MaterialApp(
        locale: locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(body: BeaconLobbyChat()),
        ),
      ),
    ),
  );
  // The chat has ongoing animations; settle only the loading/scroll frames.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(_loadInter);
  setUp(() {
    if (!GetIt.I.isRegistered<Logger>()) {
      GetIt.I.registerSingleton<Logger>(Logger('questions-phone-legibility'));
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

  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final locale in [const Locale('en'), const Locale('ru')]) {
    testWidgets(
      'Questions update names its location and keeps its time visible in ${locale.languageCode} at 375 px',
      (tester) async {
        RelativeTimestampTicker.debugClock = () => _now;
        addTearDown(() => RelativeTimestampTicker.debugClock = null);
        await _pumpCard(
          tester,
          newestUpdate: _questionsMessage('Bob R7'),
          locale: locale,
        );
        final row = find.byType(AttentionMiniCard);
        final headline = locale.languageCode == 'ru'
            ? 'Bob R7 · Новое сообщение в вопросах'
            : 'Bob R7 · New message in Questions';
        final time = locale.languageCode == 'ru' ? 'Только что' : 'Just now';
        _expectFullyVisible(
          tester,
          find.descendant(of: row, matching: find.text(headline)),
          headline,
          within: row,
        );
        _expectFullyVisible(
          tester,
          find.descendant(of: row, matching: find.text(time)),
          time,
          within: row,
        );
      },
    );
    testWidgets(
      'Questions unread divider keeps its label and count visible inside chat in ${locale.languageCode} at 375 px',
      (tester) async {
        await _pumpQuestionsChat(tester, locale);
        expect(find.byType(BeaconLobbyChat), findsOneWidget);
        expect(find.byType(BasicChatBody), findsOneWidget);
        expect(find.byType(RoomMessageTile), findsNWidgets(3));
        final divider = find.descendant(
          of: find.byType(BasicChatBody),
          matching: find.byType(RoomUnreadDivider),
        );
        expect(divider, findsOneWidget);
        expect(tester.widget<RoomUnreadDivider>(divider).unreadCount, 3);
        _expectFullyVisible(
          tester,
          find.descendant(
            of: divider,
            matching: find.text(
              lookupL10n(locale).beaconRoomUnreadDividerCount(3),
            ),
          ),
          '${locale.languageCode} unread label and count',
          within: divider,
        );
      },
    );
  }
}
