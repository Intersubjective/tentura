import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_create/fake_beacon_ports.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

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
        'childBeaconId': 'Bchild0000001',
        'sourceMessageId': _sourceId,
        'title': 'Лестница',
        if (post) 'invitedCount': 2,
      }),
  _messageRow(_sourceId, _sourceText, 1),
  _messageRow('Mother0000001', _otherText, 0),
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
