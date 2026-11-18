import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_host_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_screen_harness.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

const _childId = 'Bchild0000001';
const _ordinaryId = 'Mordinary0001';
const _sourceId = 'Msource000001';
const _noticeId = 'Mnotice000001';
const _sourceText = 'Нужна лестница';
const _otherText = 'Есть краска';
const _locale = Locale('ru');

Map<String, dynamic> _messageRow(String id, String body, int minute) =>
    roomHintWireMessageRow(
      id: id,
      authorId: roomHintWireViewerId,
      authorTitle: 'Автор',
      createdAt: DateTime.utc(2026, 6, 30, 12, minute).toIso8601String(),
      body: body,
    );

List<Map<String, dynamic>> _roomRows({
  bool hasChild = false,
  bool post = false,
}) => [
  if (hasChild)
    _messageRow(_noticeId, '', 2)
      ..['systemMessageKind'] = BeaconRoomSystemMessageKind.childCreated
      ..['systemPayloadJson'] = jsonEncode({
        'version': 1,
        'kind': 'childCreated',
        'childBeaconId': _childId,
        'sourceMessageId': _sourceId,
        'title': 'Лестница',
        if (post) 'invitedCount': 2,
      }),
  _messageRow(_sourceId, _sourceText, 1),
  _messageRow('Mother0000001', _otherText, 0),
];

Map<String, dynamic> _messageWithChild(
  String id,
  String text,
  int minute,
  String? childId,
) => _messageRow(id, text, minute)..['promotedChildBeaconId'] = childId;

List<Map<String, dynamic>> _newerPage() => [
  for (var index = 49; index >= 0; index--)
    _messageRow(
      'Mrecent${index.toString().padLeft(6, '0')}',
      'Сообщение $index',
      index + 3,
    ),
];

Future<void> _settleWire(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(
      BurstCoalescer.window + const Duration(milliseconds: 600),
    ),
  );
  await tester.pumpAndSettle();
}

Future<RoomCubit> _openRoom(
  WidgetTester tester,
  RoomHintWire wire,
  RoomCapabilities capabilities,
) async {
  final repo = RoomOverRealHintWireRepository(wire.repository);
  final cubit = (await tester.runAsync(() async {
    final cubit = RoomCubit(
      beaconId: kRoomCubitFakeBeaconId,
      beaconRoomCase: roomCubitMakeCase(
        repo,
        realtimeSyncCase: RealtimeSyncCase(wire.realtime),
      ),
      coordinationItemRoomSync: CoordinationItemRoomSync(),
      presenceRepository: roomCubitFakePresenceRepository(),
      effects: FakeUiEffectPort(),
      capabilities: capabilities,
    );
    addTearDown(() => tester.runAsync(cubit.close));
    await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
    cubit.syncBeaconStatus(BeaconStatus.open, authorId: roomHintWireViewerId);
    return cubit;
  }))!;

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(
            const Profile(id: roomHintWireViewerId, displayName: 'Автор'),
          ),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: _locale,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: BeaconRoomBody(
              enableComposer: false,
              capabilities: capabilities,
              postBuddingEnabled: capabilities.isPost,
            ),
          ),
        ),
      ),
    ),
  );
  await _settleWire(tester);
  return cubit;
}

void _expectLoadedChildNotice(RoomCubit room) {
  final notice = room.state.messages.singleWhere((m) => m.id == _noticeId);
  expect(
    notice.hierarchyPayload,
    isA<RoomMessageHierarchyChildCreated>().having(
      (payload) => payload.sourceMessageId,
      'source message',
      _sourceId,
    ),
  );
}

Finder _sheetText(String text) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(text),
);

Future<void> _openActions(WidgetTester tester, String body) async {
  final message = find.byWidgetPredicate(
    (widget) => widget is RoomMessageTextBody && widget.display == body,
  );
  expect(message, findsOneWidget);
  await tester.longPressAt(tester.getTopLeft(message) + const Offset(8, 8));
  await tester.pumpAndSettle();
  expect(find.byType(BottomSheet), findsOneWidget);
}

Future<void> _closeActions(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(BottomSheet))).pop();
  await tester.pumpAndSettle();
}

// The test replaces the router outlet with a placeholder, then renders the
// destination using the route arguments produced by the real host.
class _MessageLinkHost extends BeaconViewHostScreen {
  const _MessageLinkHost()
    : super(id: kRoomCubitFakeBeaconId, messageId: _sourceId);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _MessageLinkRouter extends BeaconViewHarnessRouter {
  BeaconViewOperationalRoute? destination;

  @override
  Future<T?> replace<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async {
    if (route is BeaconViewOperationalRoute) destination = route;
    return null;
  }
}

void main() {
  final l10n = lookupL10n(_locale);

  Future<RoomHintWire> startWire(
    WidgetTester tester,
    RoomHintWireServer server,
  ) async {
    await usePhoneSurface(tester);
    addTearDown(GetIt.I.reset);
    registerRoomCubitProfileCubit(roomHintWireViewerId);
    final write = FakeBeaconWritePort();
    final hierarchy = buildBeaconHierarchyCaseForTest(
      FakeBeaconHierarchyRepositoryPort(),
      createCase: BeaconCreateCase(write, FakeBeaconImagePort()),
      beacons: write,
      commandStore: InMemoryBeaconChildCommandStore(),
    );
    GetIt.I
      ..registerSingleton<BeaconHierarchyCase>(hierarchy)
      ..registerSingleton<ImageRepository>(ImageRepository())
      ..registerSingleton<ClipboardImageRepository>(
        ClipboardImageRepository(),
      );
    final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
    addTearDown(() => tester.runAsync(wire.close));
    return wire;
  }

  group('Published child on room messages', () {
    for (final targetOnly in [false, true]) {
      test(
        targetOnly
            ? 'the direct lookup maps both child IDs and nulls from the wire'
            : 'the message page maps both child IDs and nulls from the wire',
        () async {
          final promoted = _messageWithChild(
            _sourceId,
            _sourceText,
            1,
            _childId,
          );
          final ordinary = _messageWithChild(_ordinaryId, _otherText, 0, null);
          final server = RoomHintWireServer()
            ..messageRows = [promoted, ordinary]
            ..messageTargets.addAll({
              _sourceId: promoted,
              _ordinaryId: ordinary,
            });
          final wire = await RoomHintWire.start(server);
          addTearDown(wire.close);
          final repository = wire.repository;
          final List<RoomMessage> rows;
          if (targetOnly) {
            rows = [
              for (final id in [_sourceId, _ordinaryId])
                (await repository.fetchMessageTarget(
                  beaconId: kRoomCubitFakeBeaconId,
                  messageId: id,
                ))!,
            ];
            expect(server.requestedMessageTargetIds, [_sourceId, _ordinaryId]);
          } else {
            rows = await repository.fetchMessages(
              beaconId: kRoomCubitFakeBeaconId,
            );
          }
          expect(
            rows.map((row) => row.id),
            unorderedEquals([_sourceId, _ordinaryId]),
          );
          for (final (id, expectedChildId) in [
            (_sourceId, _childId),
            (_ordinaryId, null),
          ]) {
            final actual = rows.singleWhere((row) => row.id == id);
            expect(
              actual.promotedChildBeaconId,
              expectedChildId,
              reason: 'Message $id must carry the wire child ID.',
            );
            final different = actual.copyWith(
              promotedChildBeaconId: expectedChildId == null ? _childId : null,
            );
            expect(
              actual,
              isNot(equals(different)),
              reason: 'The child ID must distinguish RoomMessage values.',
            );
          }
        },
      );
    }

    testWidgets('reply jumps offer child creation only for the ordinary '
        'message outside the current page', (tester) async {
      final server = RoomHintWireServer()
        ..messageRows = _roomRows(hasChild: true)
        ..messageTargets[_sourceId] = _messageWithChild(
          _sourceId,
          _sourceText,
          1,
          _childId,
        )
        ..messageTargets[_ordinaryId] = _messageWithChild(
          _ordinaryId,
          _otherText,
          0,
          null,
        );
      final wire = await startWire(tester, server);
      const request = RoomCapabilities.request();
      final loaded = await _openRoom(tester, wire, request);
      _expectLoadedChildNotice(loaded);
      final sourceTile = find.byWidgetPredicate(
        (widget) => widget is RoomMessageTile && widget.message.id == _sourceId,
      );
      expect(
        find.descendant(
          of: sourceTile,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is BeaconChildPromotionFooter &&
                widget.childBeaconId == _childId,
          ),
        ),
        findsOneWidget,
      );
      await _openActions(tester, _sourceText);
      expect(_sheetText(l10n.beaconCreateChildRequest), findsNothing);
      await _closeActions(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      server.messageRows = _newerPage();
      final room = await _openRoom(tester, wire, request);
      expect(room.state.messages, hasLength(50));
      final initialIds = room.state.messages.map((message) => message.id);
      expect(
        initialIds.toSet().intersection({_sourceId, _noticeId, _ordinaryId}),
        isEmpty,
      );
      for (final (id, text) in [
        (_ordinaryId, _otherText),
        (_sourceId, _sourceText),
      ]) {
        expect(
          await tester.runAsync(
            () => room
                .jumpToRepliedMessage(id)
                .timeout(const Duration(seconds: 5)),
          ),
          isTrue,
        );
        await _settleWire(tester);
        expect(server.requestedMessageTargetIds.last, id);
        expect(
          room.state.messages.map((message) => message.id),
          isNot(contains(_noticeId)),
        );
        await _openActions(tester, text);
        expect(
          _sheetText(l10n.beaconCreateChildRequest),
          id == _ordinaryId ? findsOneWidget : findsNothing,
        );
        await _closeActions(tester);
      }
    });

    testWidgets('a Request message link hides child creation for a promoted '
        'message outside the current page', (tester) async {
      final server = RoomHintWireServer()
        ..messageRows = _newerPage()
        ..messageTargets[_sourceId] = _messageWithChild(
          _sourceId,
          _sourceText,
          1,
          _childId,
        );
      final wire = await startWire(tester, server);
      final roomCase = roomCubitMakeCase(
        RoomOverRealHintWireRepository(wire.repository),
        realtimeSyncCase: RealtimeSyncCase(wire.realtime),
      );
      GetIt.I
        ..registerSingleton<BeaconThreadsCase>(roomCase)
        ..registerSingleton<BeaconViewCase>(buildTestBeaconViewCase())
        ..registerSingleton<UiEffectPort>(FakeUiEffectPort());
      final router = _MessageLinkRouter();
      await tester.pumpWidget(
        StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MaterialApp(
            theme: TenturaTheme.light(),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            locale: _locale,
            home: BlocProvider<ProfileCubit>.value(
              value: GetIt.I<ProfileCubit>(),
              child: Builder(
                builder: (context) =>
                    const _MessageLinkHost().wrappedRoute(context),
              ),
            ),
          ),
        ),
      );
      await _settleWire(tester);
      expect(server.requestedMessageTargetIds, contains(_sourceId));
      final destination = router.destination;
      expect(destination, isNotNull);
      final args = destination!.args!;
      expect(args.messageId, _sourceId);
      await tester.pumpWidget(const SizedBox.shrink());

      final roomHost = ThreadHostCubit(
        beaconId: kRoomCubitFakeBeaconId,
        roomCubitFactory:
            ({
              required beaconId,
              threadItemId,
              initialUnreadAnchorAt,
              capabilities = const RoomCapabilities.request(),
            }) => RoomCubit(
              beaconId: beaconId,
              threadItemId: threadItemId,
              initialUnreadAnchorAt: initialUnreadAnchorAt,
              capabilities: capabilities,
              beaconRoomCase: roomCase,
              coordinationItemRoomSync: CoordinationItemRoomSync(),
              presenceRepository: roomCubitFakePresenceRepository(),
              effects: FakeUiEffectPort(),
            ),
      );
      try {
        await pumpBeaconViewHarness(
          tester,
          size: kPhoneSurface,
          beaconState: beaconViewHarnessAuthorState(
            beaconId: kRoomCubitFakeBeaconId,
            authorId: roomHintWireViewerId,
          ),
          threadsState: beaconViewHarnessThreadsState(
            authorId: roomHintWireViewerId,
          ),
          host: roomHost,
          viewTab: args.viewTab,
          threadId: args.threadId,
          messageId: args.messageId,
          locale: _locale,
        );
        await _settleWire(tester);
        final room = roomHost.roomCubit!;
        final loadedIds = room.state.messages.map((message) => message.id);
        expect(loadedIds, contains(_sourceId));
        expect(loadedIds, isNot(contains(_noticeId)));
        final messageList = find.descendant(
          of: find.byType(BasicChatBody),
          matching: find.byType(ListView),
        );
        // Expose the fetched source even when initial unread positioning
        // leaves the chat at the newest messages.
        final controller = tester.widget<ListView>(messageList).controller!;
        controller.jumpTo(controller.position.minScrollExtent);
        await tester.pumpAndSettle();
        await _openActions(tester, _sourceText);
        expect(_sheetText(l10n.beaconCreateChildRequest), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        final close = roomHost.close();
        await _settleWire(tester);
        await close;
      }
    });
  });

  testWidgets('only the unlinked Request message offers child creation, '
      'while linked messages retain plan editing and Post budding', (
    tester,
  ) async {
    final server = RoomHintWireServer()
      ..messageRows = _roomRows(hasChild: true, post: true);
    final wire = await startWire(tester, server);
    final post = await _openRoom(tester, wire, const RoomCapabilities.post());
    _expectLoadedChildNotice(post);
    await _openActions(tester, _sourceText);
    expect(_sheetText(l10n.postBudAction), findsOneWidget);
    await _closeActions(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    server.messageRows = _roomRows(hasChild: true);
    final request = await _openRoom(
      tester,
      wire,
      const RoomCapabilities.request(),
    );
    _expectLoadedChildNotice(request);

    await _openActions(tester, _otherText);
    expect(_sheetText(l10n.beaconCreateChildRequest), findsOneWidget);
    await _closeActions(tester);

    await _openActions(tester, _sourceText);
    expect(
      _sheetText(l10n.beaconRoomActionUpdatePlanFromMessage),
      findsOneWidget,
    );
    final russianHeader = _sheetText('Преобразовать в…');
    expect(russianHeader, findsOneWidget);
    expect(tester.widget<Text>(russianHeader).data, isNot(contains('...')));
    expect(_sheetText(l10n.beaconCreateChildRequest), findsNothing);
  });

  testWidgets('a new child notice removes child creation from the already '
      'open Request room', (tester) async {
    final server = RoomHintWireServer()..messageRows = _roomRows();
    final wire = await startWire(tester, server);
    final room = await _openRoom(
      tester,
      wire,
      const RoomCapabilities.request(),
    );
    await _openActions(tester, _sourceText);
    expect(_sheetText(l10n.beaconCreateChildRequest), findsOneWidget);
    await _closeActions(tester);

    final mountedRoom = tester.state(find.byType(BeaconRoomBody));
    server.messageRows = _roomRows(hasChild: true);
    await tester.runAsync(() async {
      wire.socket.frames.add(
        jsonEncode({
          'type': 'subscription',
          'path': 'entity_changes',
          'payload': {
            'entity': 'room_message',
            'id': kRoomCubitFakeBeaconId,
            'event': 'insert',
            'actor_user_id': 'Uother0000001',
            'message_id': _noticeId,
          },
        }),
      );
    });
    await _settleWire(tester);

    expect(tester.state(find.byType(BeaconRoomBody)), same(mountedRoom));
    _expectLoadedChildNotice(room);
    await _openActions(tester, _sourceText);
    expect(
      _sheetText(l10n.beaconRoomActionUpdatePlanFromMessage),
      findsOneWidget,
    );
    expect(_sheetText(l10n.beaconCreateChildRequest), findsNothing);
  });
}
