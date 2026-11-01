// An open Request chat shows other members' poll votes and reads live, over
// the real transport path: the server's `entity_changes` frame enters the
// socket, crosses the real RemoteApiService, InvalidationService and
// BeaconThreadsRepository into the room cubit, and the refetch it triggers
// goes through the real GraphQL mapping (only the socket and the HTTP
// transport are faked; see support/room_hint_wire_harness.dart).
//
// Wire shapes are the server's (packages/server
// websocket_path_entity_changes.dart): `{type: subscription, path:
// entity_changes, payload: {entity, id: <request id>, event, actor_user_id,
// [seen_user_id, last_seen_at]}}`.
//
// Phone (375×667) in the ru locale: the key text must render in full.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/util/burst_coalescer.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';
import 'support/room_hint_wire_harness.dart';

const _viewerName = 'Я';
const _pollAuthorId = 'Upollauthor01';
const _readerId = 'Ureader000001';
const _readerName = 'Ольга Смирнова';
const _pollId = 'Ppolllive0001';

final _sentAt = DateTime.utc(2026, 6, 30, 12);

String _pollJson({required int yes, required int no}) => jsonEncode({
  'id': _pollId,
  'question': 'Встречаемся в понедельник?',
  'pollType': 'single',
  'isAnonymous': true,
  'allowRevote': true,
  'myVariantIds': <String>[],
  'totalVotes': yes + no,
  'variants': [
    {'id': 'v-yes', 'description': 'Да', 'votesCount': yes},
    {'id': 'v-no', 'description': 'Нет', 'votesCount': no},
  ],
});

Map<String, dynamic> _pollRow({required int yes, required int no}) =>
    roomHintWireMessageRow(
      id: 'Mpolllive0001',
      authorId: _pollAuthorId,
      authorTitle: 'Автор опроса',
      createdAt: _sentAt.toIso8601String(),
      linkedPollingId: _pollId,
      pollDataJson: _pollJson(yes: yes, no: no),
    );

BeaconParticipant _admitted(String userId, String title) => BeaconParticipant(
  id: 'p-$userId',
  beaconId: kRoomCubitFakeBeaconId,
  userId: userId,
  userTitle: title,
  role: BeaconParticipantRoleBits.helper,
  status: 0,
  roomAccess: RoomAccessBits.admitted,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// Lets a pushed frame cross the real stack (InvalidationService batches
/// non-message hints for 100 ms, the room coalesces hint refetches for one
/// [BurstCoalescer.window]) and the refetch over the fake transport finish,
/// then rebuilds.
Future<void> _settleWire(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(
      BurstCoalescer.window + const Duration(milliseconds: 600),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('An open Request chat over the real realtime stack', () {
    late RoomHintWireServer server;
    late RoomHintWire wire;
    late RoomCubit cubit;

    Future<void> openRoom(WidgetTester tester) async {
      await usePhoneSurface(tester);
      await GetIt.I.reset();
      addTearDown(GetIt.I.reset);
      registerRoomCubitProfileCubit(roomHintWireViewerId);
      GetIt.I
        ..registerSingleton<ImageRepository>(ImageRepository())
        ..registerSingleton<ClipboardImageRepository>(
          ClipboardImageRepository(),
        );

      wire = (await tester.runAsync(() => RoomHintWire.start(server)))!;
      addTearDown(() => tester.runAsync(wire.close));

      final repo = RoomOverRealHintWireRepository(wire.repository)
        ..participants = [
          _admitted(roomHintWireViewerId, _viewerName),
          _admitted(_pollAuthorId, 'Автор опроса'),
          _admitted(_readerId, _readerName),
        ];
      await tester.runAsync(() async {
        cubit = roomCubitForTest(
          repo,
          effects: FakeUiEffectPort(),
          realtimeSyncCase: RealtimeSyncCase(wire.realtime),
        );
        await awaitRoomCubitLoad(cubit);
        cubit.syncBeaconStatus(BeaconStatus.open);
      });
      addTearDown(() => tester.runAsync(cubit.close));

      const viewer = Profile(
        id: roomHintWireViewerId,
        displayName: _viewerName,
      );
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
      await _settleWire(tester);
    }

    setUp(() => server = RoomHintWireServer());

    testWidgets(
      "another member's vote pushed by the server updates the poll card's "
      'counts without a reload (phone, ru)',
      (tester) async {
        final l10n = L10nRu();
        server.messageRows = [_pollRow(yes: 0, no: 0)];
        await openRoom(tester);

        final card = find.byType(RoomPollCard);
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.beaconRoomPollVotesCount(0)),
          ),
          findsOneWidget,
        );

        // Two other members vote; the server now reports their votes and
        // pushes the room_poll hint to everyone with the chat open.
        server.messageRows = [_pollRow(yes: 2, no: 0)];
        final listQueriesBefore = server.queried
            .where((q) => q == 'RoomMessageList')
            .length;
        await tester.runAsync(() async => wire.pushPollVote());
        await _settleWire(tester);

        expect(
          server.queried.where((q) => q == 'RoomMessageList').length,
          greaterThan(listQueriesBefore),
          reason: 'the poll hint must refetch the chat from the server',
        );
        final total = find.descendant(
          of: card,
          matching: find.text(l10n.beaconRoomPollVotesCount(2)),
        );
        expect(total, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.text(l10n.beaconRoomPollVotesCount(0)),
          ),
          findsNothing,
        );
        // «2 голоса» renders in full on the phone.
        expect(
          tester.widget<Text>(total).overflow,
          isNot(TextOverflow.ellipsis),
        );
        expect(tester.getRect(total).right, lessThanOrEqualTo(375));
      },
    );

    testWidgets(
      "a member's read pushed by the server replaces «nobody has read this "
      'yet» in the open message actions sheet (phone, ru)',
      (tester) async {
        final l10n = L10nRu();
        server.messageRows = [
          roomHintWireMessageRow(
            id: 'Mownmessage01',
            authorId: roomHintWireViewerId,
            authorTitle: _viewerName,
            createdAt: _sentAt.toIso8601String(),
            body: 'Кто придёт в понедельник?',
          ),
        ];
        await openRoom(tester);

        final body = find.byType(RoomMessageTextBody);
        expect(body, findsOneWidget);
        await tester.longPressAt(tester.getTopLeft(body) + const Offset(8, 8));
        await tester.pumpAndSettle();
        final sheet = find.byType(BottomSheet);
        expect(sheet, findsOneWidget);
        expect(
          find.descendant(
            of: sheet,
            matching: find.text(l10n.beaconRoomReadByNobodyYet),
          ),
          findsOneWidget,
        );

        // The member reads the message; the server pushes room_seen_peer
        // while the author keeps the sheet open.
        await tester.runAsync(
          () async => wire.pushSeenPeer(
            seenUserId: _readerId,
            lastSeenAt: _sentAt.add(const Duration(minutes: 1)),
          ),
        );
        await _settleWire(tester);

        expect(
          cubit.state.readWatermarks[_readerId],
          isNotNull,
          reason: 'the frame must reach the room; only the sheet may lag',
        );
        expect(
          find.descendant(
            of: sheet,
            matching: find.text(l10n.beaconRoomReadByNobodyYet),
          ),
          findsNothing,
          reason: 'the open sheet must drop «nobody has read this yet»',
        );
        final readBy = find.descendant(
          of: sheet,
          matching: find.text(_readerName),
        );
        expect(readBy, findsOneWidget);
        expect(
          tester.widget<Text>(readBy).overflow,
          isNot(TextOverflow.ellipsis),
        );
        expect(tester.getRect(readBy).right, lessThanOrEqualTo(375));
      },
    );
  });
}
