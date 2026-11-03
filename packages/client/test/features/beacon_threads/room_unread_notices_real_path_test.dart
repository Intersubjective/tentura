import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_unread_divider.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

final _anchor = DateTime.utc(2026, 10, 21, 9);

Map<String, dynamic> _noticeRow(int marker) => {
  ...roomHintWireMessageRow(
    id: 'notice',
    authorId: 'Uhelper000001',
    authorTitle: 'Омар',
    createdAt: _anchor.add(const Duration(minutes: 1)).toIso8601String(),
  ),
  'semanticMarker': marker,
  'systemPayloadJson': jsonEncode({
    'leftUserId': 'Uhelper000001',
    'withdrawReason': 'timing',
    'removedUserId': 'Uhelper000001',
    'joinedUserId': 'Uhelper000001',
    'actorUserId': 'Uhelper000001',
    'admissionReason': 'accept',
  }),
};

Map<String, dynamic> _statusNoticeRow() => {
  ...roomHintWireMessageRow(
    id: 'notice',
    authorId: 'Uhelper000001',
    authorTitle: 'Омар',
    createdAt: _anchor.add(const Duration(minutes: 1)).toIso8601String(),
  ),
  'systemMessageKind': BeaconRoomSystemMessageKind.statusChanged,
  'systemPayloadJson': jsonEncode({
    'version': 1,
    'fromStatus': 0,
    'toStatus': 8,
    'reason': 'enoughHelp',
  }),
};

Finder _messageTile(String id) => find.byWidgetPredicate(
  (widget) => widget is RoomMessageTile && widget.message.id == id,
);

void _expectDividerAfterNotice(WidgetTester tester, String unreadId) {
  final notice = _messageTile('notice');
  final message = _messageTile(unreadId);
  final divider = find.byType(RoomUnreadDivider);
  expect(notice, findsOneWidget);
  expect(message, findsOneWidget);
  expect(divider, findsOneWidget);
  expect(
    tester.getBottomLeft(notice).dy,
    lessThanOrEqualTo(tester.getTopLeft(divider).dy),
    reason: 'the read-only notice must precede the unread band',
  );
  expect(
    tester.getBottomLeft(divider).dy,
    lessThanOrEqualTo(tester.getTopLeft(message).dy),
    reason: 'the unread band must precede the first unread contribution',
  );
}

Future<RoomCubit> _openRoom(
  WidgetTester tester,
  RoomHintWireServer server,
) async {
  await usePhoneSurface(tester);
  await GetIt.I.reset();
  addTearDown(GetIt.I.reset);
  registerRoomCubitProfileCubit(roomHintWireViewerId);
  GetIt.I
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());

  final wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
  addTearDown(() => tester.runAsync(wire.close));
  final repository = RoomOverRealHintWireRepository(wire.repository);
  addTearDown(repository.dispose);
  final watermarks = RoomReadWatermarkStore.testing()
    ..confirmSynced(kRoomCubitFakeBeaconId, _anchor);
  addTearDown(watermarks.dispose);
  late RoomCubit cubit;
  await tester.runAsync(() async {
    cubit = roomCubitForTest(repository, watermarkStore: watermarks);
    await awaitRoomCubitLoad(cubit).timeout(const Duration(seconds: 5));
    cubit.syncBeaconStatus(BeaconStatus.open);
  });
  addTearDown(() => tester.runAsync(cubit.close));

  const viewer = Profile(id: roomHintWireViewerId, displayName: 'Я');
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<RoomCubit>.value(value: cubit),
        BlocProvider<ProfileCubit>.value(
          value: RoomBodyHarnessProfileCubit(viewer),
        ),
        BlocProvider<PresenceCubit>.value(
          value: RoomBodyHarnessPresenceCubit(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const TenturaResponsiveScope(
          child: Scaffold(body: BeaconRoomBody(enableComposer: false)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(server.queried, contains('RoomMessageList'));
  expect(cubit.state.firstLoadDone, isTrue);
  expect(cubit.state.loadError, isNull);
  return cubit;
}

void main() {
  for (final entry in {
    'leave': BeaconRoomSemanticMarker.participantLeft,
    'removal': BeaconRoomSemanticMarker.participantRemoved,
    'join': BeaconRoomSemanticMarker.participantJoined,
  }.entries) {
    testWidgets(
      'RU phone Discussion shows a ${entry.key} notice without a new messages divider',
      (tester) async {
        final server = RoomHintWireServer()
          ..messageRows = [_noticeRow(entry.value)];
        final cubit = await _openRoom(tester, server);
        expect(cubit.state.messages.single.semanticMarker, entry.value);
        // The notice remains visible; removing the row is not a valid fix.
        final copy = switch (entry.key) {
          'leave' => 'Омар покинул(а) запрос',
          'removal' => 'Омар',
          _ => 'Омар',
        };
        expect(find.textContaining(copy, findRichText: true), findsWidgets);
        expect(tester.takeException(), isNull);
        expect(find.byType(RoomUnreadDivider), findsNothing);
        expect(
          (cubit.state.unreadBandCount, cubit.state.unreadBandMessageId),
          (0, null),
        );
      },
    );
  }

  testWidgets(
    'RU phone Discussion shows a status change without a new messages divider',
    (tester) async {
      final server = RoomHintWireServer()..messageRows = [_statusNoticeRow()];
      final cubit = await _openRoom(tester, server);
      expect(cubit.state.messages.single.semanticMarker, isNull);
      expect(
        cubit.state.messages.single.systemMessageKind,
        BeaconRoomSystemMessageKind.statusChanged,
      );
      final ru = lookupL10n(const Locale('ru'));
      expect(
        find.text(
          ru.roomStatusChangedByActor(
            'Омар',
            ru.beaconStatusRowOpen,
            ru.coordinationEnoughHelp,
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(RoomUnreadDivider), findsNothing);
      expect(
        (cubit.state.unreadBandCount, cubit.state.unreadBandMessageId),
        (0, null),
      );
    },
  );

  final ru = lookupL10n(const Locale('ru'));
  final systemNotices =
      <
        String,
        ({
          int kind,
          int? marker,
          String body,
          Map<String, Object?> payload,
          String visibleText,
        })
      >{
        'hierarchy lifecycle': (
          kind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
          marker: null,
          body: '',
          payload: {
            'version': 1,
            'kind': 'hierarchyLifecycle',
            'eventId': 'event-1',
            'targetBeaconId': kRoomCubitFakeBeaconId,
            'direction': 'child',
            'toStatus': 'closed',
            'occurredAt': _anchor.toIso8601String(),
            'sourceDeleted': false,
            'sourceTitle': 'Доставка',
          },
          visibleText: 'Доставка',
        ),
        'child creation': (
          kind: BeaconRoomSystemMessageKind.childCreated,
          marker: null,
          body: '',
          payload: {
            'version': 1,
            'kind': 'childCreated',
            'childBeaconId': 'Bchild000001',
            'title': 'Встреча соседей',
            'invitedCount': 0,
          },
          visibleText: ru.roomBudNoticeNoInvites('Омар', 'Встреча соседей'),
        ),
        'closure story': (
          kind: BeaconRoomSystemMessageKind.closureStory,
          marker: null,
          body: 'Всё получилось, спасибо',
          payload: {},
          visibleText: 'Всё получилось, спасибо',
        ),
        'conversion to Request': (
          kind: BeaconRoomSystemMessageKind.convertedToRequest,
          marker: null,
          body: '',
          payload: {},
          visibleText: ru.roomConvertedToRequestNotice('Омар'),
        ),
        'Post closure': (
          kind: BeaconRoomSystemMessageKind.postClosed,
          marker: null,
          body: '',
          payload: {'reason': 'expired'},
          visibleText: ru.roomPostExpiredNotice,
        ),
        'plan update': (
          kind: BeaconRoomSystemMessageKind.plan,
          marker: BeaconRoomSemanticMarker.planStepsDone,
          body: '',
          payload: {
            'ticks': [
              {
                'stepId': 'step-1',
                'title': 'Забрать ключи',
                'actorId': 'Uhelper000001',
                'assigneeId': 'Uhelper000001',
                'at': _anchor.toIso8601String(),
              },
            ],
          },
          visibleText: 'Забрать ключи',
        ),
        'Request title edit': (
          kind: BeaconRoomSystemMessageKind.requestEdited,
          marker: null,
          body: '',
          payload: {
            'version': 1,
            'field': 'title',
            'from': 'Прогулка',
            'to': 'Поход в парк',
          },
          visibleText: 'Поход в парк',
        ),
      };
  for (final entry in systemNotices.entries) {
    testWidgets(
      'RU phone Discussion shows a ${entry.key} notice without a new messages divider',
      (tester) async {
        final notice = entry.value;
        final server = RoomHintWireServer()
          ..messageRows = [
            {
              ...roomHintWireMessageRow(
                id: 'notice',
                authorId: 'Uhelper000001',
                authorTitle: 'Омар',
                body: notice.body,
                createdAt: _anchor
                    .add(const Duration(minutes: 1))
                    .toIso8601String(),
              ),
              'semanticMarker': notice.marker,
              'systemMessageKind': notice.kind,
              'systemPayloadJson': jsonEncode(notice.payload),
            },
          ];
        final cubit = await _openRoom(tester, server);
        final message = cubit.state.messages.single;
        expect(message.systemMessageKind, notice.kind);
        expect(message.semanticMarker, notice.marker);
        expect(message.createdAt, _anchor.add(const Duration(minutes: 1)));
        expect(
          find.textContaining(notice.visibleText, findRichText: true),
          findsOneWidget,
          reason: 'the server notice remains visible in the Discussion',
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(RoomUnreadDivider), findsNothing);
        expect(
          (cubit.state.unreadBandCount, cubit.state.unreadBandMessageId),
          (0, null),
        );
      },
    );
  }

  for (final systemNotice in [false, true]) {
    for (final semantic in [false, true]) {
      testWidgets(
        'RU phone Discussion places its new messages divider between a ${systemNotice ? 'status change' : 'leave notice'} and a ${semantic ? 'fact edit' : 'member message'}',
        (tester) async {
          final server = RoomHintWireServer()
            ..messageRows = [
              systemNotice
                  ? _statusNoticeRow()
                  : _noticeRow(BeaconRoomSemanticMarker.participantLeft),
              roomHintWireMessageRow(
                id: 'message',
                authorId: 'Upeer0000001',
                authorTitle: 'Анна',
                body: 'Я помогу',
                createdAt: _anchor
                    .add(const Duration(minutes: 2))
                    .toIso8601String(),
              )..addAll(
                semantic
                    ? {
                        'body': '',
                        'semanticMarker': BeaconRoomSemanticMarker.factEdited,
                        'systemPayloadJson': jsonEncode({
                          'factCardId': 'fact-1',
                          'pinnedBy': 'Upeer0000001',
                          'factText': 'Встреча в десять',
                          'revisionSeq': 2,
                        }),
                      }
                    : <String, dynamic>{},
              ),
            ];
          final cubit = await _openRoom(tester, server);
          expect(
            find.textContaining(
              semantic ? 'Встреча в десять' : 'Я помогу',
              findRichText: true,
            ),
            findsOneWidget,
          );
          if (semantic) {
            expect(
              cubit.state.messages.last.semanticMarker,
              BeaconRoomSemanticMarker.factEdited,
            );
            expect(cubit.state.messages.last.systemMessageKind, isNull);
          }
          _expectDividerAfterNotice(tester, 'message');
          final label = lookupL10n(
            const Locale('ru'),
          ).beaconRoomUnreadDividerCount(1);
          expect(find.text(label), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(
            (cubit.state.unreadBandCount, cubit.state.unreadBandMessageId),
            (1, 'message'),
          );
        },
      );
    }
  }
}
