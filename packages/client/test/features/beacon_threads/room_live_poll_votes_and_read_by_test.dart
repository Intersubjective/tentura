// An open Request chat must show other members' poll votes and reads live:
// the realtime room hints for a poll vote and for a read mark update what the
// viewer sees (poll counts, the «Read by» row of the message actions sheet)
// without a reload.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../../support/burst_coalescer_test_timing.dart';
import '../../support/phone_surface.dart';
import 'room_cubit_fakes.dart';
import 'support/room_body_harness.dart';

const _pollId = 'poll-live-1';
const _pollMessageId = 'msg-poll-live-1';
const _readerId = 'peer-reader';
const _readerName = 'Ольга Смирнова';

final _messageCreatedAt = DateTime.utc(2026, 6, 30, 12);

String _pollJson({required int monday, required int tuesday}) => jsonEncode({
  'id': _pollId,
  'question': 'Which day?',
  'pollType': 'single',
  'isAnonymous': true,
  'allowRevote': true,
  'myVariantIds': <String>[],
  'totalVotes': monday + tuesday,
  'variants': [
    {'id': 'v-mon', 'description': 'Monday', 'votesCount': monday},
    {'id': 'v-tue', 'description': 'Tuesday', 'votesCount': tuesday},
  ],
});

RoomMessage _pollMessage({required int monday, required int tuesday}) =>
    RoomMessage(
      id: _pollMessageId,
      beaconId: kRoomCubitFakeBeaconId,
      authorId: 'peer-poll-author',
      body: '',
      createdAt: _messageCreatedAt,
      linkedPollingId: _pollId,
      pollDataJson: _pollJson(monday: monday, tuesday: tuesday),
    );

RoomPollData _shownPoll(RoomState state) => RoomPollData.tryParse(
  state.messages.singleWhere((m) => m.id == _pollMessageId).pollDataJson,
)!;

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

void main() {
  group('An open Request chat applies live room hints', () {
    test(
      "another member's poll vote hint updates the poll counts without a reload",
      () async {
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        final fakeRoom = FakeBeaconThreadsRepository(
          userId: kRoomCubitFakeMyUserId,
        )..messages = [_pollMessage(monday: 0, tuesday: 0)];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);
        addTearDown(cubit.close);

        final loaded = await awaitRoomCubitLoad(cubit);
        expect(_shownPoll(loaded).totalVotes, 0);

        // Two other members vote; the server now reports their votes.
        fakeRoom
          ..messages = [_pollMessage(monday: 2, tuesday: 0)]
          ..emitInvalidation(BeaconRoomEntityType.roomPoll);
        await pumpAfterHintBurst();

        final poll = _shownPoll(cubit.state);
        expect(poll.totalVotes, 2);
        expect(
          poll.variants.singleWhere((v) => v.id == 'v-mon').votesCount,
          2,
        );
        expect(cubit.state.status, isA<StateIsSuccess>());
      },
    );

    testWidgets(
      'the open message actions sheet shows a member who just read the '
      'message instead of «nobody has read this yet» (phone, ru)',
      (tester) async {
        await usePhoneSurface(tester);
        final l10n = L10nRu();
        const viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Я');
        final getIt = GetIt.I;
        await getIt.reset();
        addTearDown(getIt.reset);
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        getIt
          ..registerSingleton<ImageRepository>(ImageRepository())
          ..registerSingleton<ClipboardImageRepository>(
            ClipboardImageRepository(),
          );

        final fakeRoom =
            FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId)
              ..participants = [
                _admitted(kRoomCubitFakeMyUserId, viewer.displayName),
                _admitted(_readerId, _readerName),
              ]
              ..messages = [
                RoomMessage(
                  id: 'own-1',
                  beaconId: kRoomCubitFakeBeaconId,
                  authorId: viewer.id,
                  author: viewer,
                  body: 'Встречаемся в понедельник?',
                  createdAt: _messageCreatedAt,
                ),
              ];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);

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
        for (var i = 0; i < 10 && !cubit.state.firstLoadDone; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(cubit.state.participantsLoaded, isTrue);

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

        // The member reads the message while the author keeps the sheet open.
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomSeenPeer,
          seenPeer: RealtimeSeenPeer(
            userId: _readerId,
            lastSeenAt: _messageCreatedAt.add(const Duration(minutes: 1)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          cubit.state.readWatermarks[_readerId],
          isNotNull,
          reason: 'the room took the read hint; only the sheet may lag',
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
        // The reader's name renders in full at phone width.
        final readByText = tester.widget<Text>(readBy);
        expect(readByText.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.getRect(readBy).right, lessThanOrEqualTo(375));

        await cubit.close();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a message that arrives in the open chat is marked read for its sender '
      'without scrolling (phone, ru)',
      (tester) async {
        await usePhoneSurface(tester);
        const viewer = Profile(id: kRoomCubitFakeMyUserId, displayName: 'Я');
        final getIt = GetIt.I;
        await getIt.reset();
        addTearDown(getIt.reset);
        registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
        getIt
          ..registerSingleton<ImageRepository>(ImageRepository())
          ..registerSingleton<ClipboardImageRepository>(
            ClipboardImageRepository(),
          );

        final fakeRoom = _SeenRecordingRepository()
          ..participants = [
            _admitted(kRoomCubitFakeMyUserId, viewer.displayName),
            _admitted(_readerId, _readerName),
          ]
          ..messages = [
            RoomMessage(
              id: 'peer-1',
              beaconId: kRoomCubitFakeBeaconId,
              authorId: _readerId,
              body: 'Привет',
              createdAt: _messageCreatedAt,
            ),
          ];
        addTearDown(fakeRoom.dispose);
        final cubit = roomCubitForTest(fakeRoom);

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
        for (var i = 0; i < 10 && !cubit.state.firstLoadDone; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        fakeRoom.seenReadThrough.clear();

        final arrivedAt = _messageCreatedAt.add(const Duration(minutes: 5));
        fakeRoom.emitInvalidation(
          BeaconRoomEntityType.roomMessage,
          operation: RealtimeOperation.insert,
          messageId: 'peer-2',
          paint: RealtimeRoomMessagePaint(
            id: 'peer-2',
            beaconId: kRoomCubitFakeBeaconId,
            authorId: _readerId,
            body: 'Ты тут?',
            createdAt: arrivedAt,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Ты тут?'), findsOneWidget);

        expect(
          fakeRoom.seenReadThrough.where((at) => !at.isBefore(arrivedAt)),
          isNotEmpty,
          reason: 'the shown message must be marked read so its sender sees it',
        );

        await cubit.close();
        await tester.pumpAndSettle();
      },
    );
  });
}

class _SeenRecordingRepository extends FakeBeaconThreadsRepository {
  _SeenRecordingRepository() : super(userId: kRoomCubitFakeMyUserId);

  final seenReadThrough = <DateTime>[];

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    seenReadThrough.add(readThroughAt);
    return readThroughAt;
  }
}
