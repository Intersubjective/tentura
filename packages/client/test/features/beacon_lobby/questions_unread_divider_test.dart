import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_chat.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_unread_divider.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/test_realtime_sync.dart';
import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;
import '../my_work/my_work_test_support.dart' show buildStubAttentionCase;
import 'fake_lobby_port.dart';

const _beaconId = 'B1';
const _questionsId = 'Llobby';
const _alice = Profile(id: 'Uauthor', displayName: 'Alice');
final _at = DateTime.utc(2026, 10, 30, 12);

RoomMessage _question(int number, Profile author) => RoomMessage(
  id: 'question-$number',
  beaconId: _beaconId,
  threadItemId: _questionsId,
  authorId: author.id,
  author: author,
  body: 'Question $number',
  createdAt: _at.add(Duration(minutes: number)),
);

/// The server's persisted Questions cursor, independent of the session store.
/// The access probe uses the same cursor as countVisibleMessages on the server.
class _QuestionsServer extends FakeBeaconThreadsRepository {
  _QuestionsServer() : super(userId: _alice.id);

  DateTime? seenAt;

  int get unreadCount => messages
      .where(
        (message) =>
            message.authorId != _alice.id &&
            (seenAt == null || message.createdAt.isAfter(seenAt!)),
      )
      .length;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async => [
    for (final message in messages)
      if (message.beaconId == beaconId && message.threadItemId == threadItemId)
        message,
  ];

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    expect(beaconId, _beaconId);
    expect(threadId, _questionsId);
    if (seenAt == null || readThroughAt.isAfter(seenAt!)) {
      seenAt = readThroughAt;
    }
    return seenAt!;
  }
}

class _QuestionsAccess extends FakeLobbyPort {
  _QuestionsAccess(this.server) : super(viewerId: _alice.id);
  final _QuestionsServer server;

  @override
  Future<BeaconLobbyAccess> access(String beaconId) async =>
      (await super.access(beaconId)).copyWith(
        messageCount: server.messages.length,
        unreadCount: server.unreadCount,
      );
}

Future<void> _frames(WidgetTester tester) async {
  // Chat animations do not settle; use the bounded pump convention.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('Questions unread divider agrees with the Overview', () {
    for (final scenario in ['same session', 'supplied cursor', 'reload']) {
      testWidgets(
        switch (scenario) {
          'supplied cursor' =>
            'a new cubit given a confirmed Questions cursor marks only the new question unread',
          'reload' =>
            'after losing session state the persisted Questions unread state agrees on Overview and in chat',
          _ =>
            'after a previous visit only the newly posted question is marked unread',
        },
        (tester) async {
          tester.view.physicalSize = const Size(700, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final getIt = GetIt.I;
          await getIt.reset();
          addTearDown(getIt.reset);

          final server = _QuestionsServer()
            ..messages = [
              _question(1, const Profile(id: 'Ubob', displayName: 'Bob')),
              _question(2, const Profile(id: 'Ucarol', displayName: 'Carol')),
            ];
          addTearDown(server.dispose);
          final sync = buildTestRealtimeSync();
          addTearDown(sync.port.dispose);
          var watermarks = RoomReadWatermarkStore.testing();
          addTearDown(watermarks.dispose);
          var roomCase = roomCubitMakeCase(
            server,
            watermarkStore: watermarks,
            realtimeSyncCase: sync.case_,
          );
          final effects = RecordingEffects();
          final profile = RoomBodyHarnessProfileCubit(_alice);
          final presence = RoomBodyHarnessPresenceCubit();
          final presenceRepository = roomCubitFakePresenceRepository();
          getIt.registerSingleton<ProfileCubit>(profile);

          // Alice opens Questions after Bob and Carol have each asked once,
          // then reads to the bottom using the same action as the chat.
          final firstVisit = RoomCubit(
            beaconId: _beaconId,
            threadItemId: _questionsId,
            lobbyAccess: const BeaconLobbyAccess(canRead: true, canPost: true),
            capabilities: const RoomCapabilities.questions(),
            beaconRoomCase: roomCase,
            coordinationItemRoomSync: CoordinationItemRoomSync(),
            presenceRepository: presenceRepository,
            effects: effects,
          );
          final loaded = firstVisit.stream.firstWhere(
            (s) => s.messages.length == 2,
          );
          await tester.runAsync(() => loaded);
          await firstVisit.markReadToBottom();
          expect(server.seenAt, server.messages[1].createdAt);
          expect(server.unreadCount, 0);
          await firstVisit.close();

          // Keep the first visit's server-confirmed state. The supplied-cursor
          // case tests application of that state; the reload case starts with
          // an empty session and exposes persisted state only via server APIs.
          final persistedQuestionsCursor = server.seenAt!;
          expect(
            watermarks.syncedAt(_beaconId, threadId: _questionsId),
            persistedQuestionsCursor,
          );
          if (scenario != 'same session') {
            watermarks = RoomReadWatermarkStore.testing();
            addTearDown(watermarks.dispose);
            expect(
              watermarks.readThrough(_beaconId, threadId: _questionsId),
              isNull,
            );
            if (scenario == 'supplied cursor') {
              watermarks.confirmSynced(
                _beaconId,
                DateTime.parse(persistedQuestionsCursor.toIso8601String()),
                threadId: _questionsId,
              );
            }
            // In the reload case, do not hydrate the store from the test.
            // The production lobby access probe must supply the unread state
            // computed from the cursor persisted by the first visit.
            roomCase = roomCubitMakeCase(
              server,
              watermarkStore: watermarks,
              realtimeSyncCase: sync.case_,
            );
          }
          // This is the exact case injected into the new chat cubit below.
          // Reload must start cold; the other scenarios already have the
          // confirmed Questions cursor, separate from the main Discussion.
          expect(
            roomCase.readThrough(_beaconId, threadId: _questionsId),
            scenario == 'reload' ? null : persistedQuestionsCursor,
          );
          expect(roomCase.readThrough(_beaconId), isNull);
          server.messages = [
            ...server.messages,
            _question(3, const Profile(id: 'Ubob', displayName: 'Bob')),
          ];
          final lobbySync = FakeRealtimeSyncPort();
          addTearDown(lobbySync.dispose);
          final lobbyCase = lobbyCaseFor(_QuestionsAccess(server), lobbySync);
          final attention = buildStubAttentionCase();
          addTearDown(attention.dispose);
          getIt
            ..registerSingleton<PresenceCubit>(presence)
            ..registerSingleton<UiEffectPort>(effects)
            ..registerSingleton<AttentionCase>(attention)
            ..registerSingleton<BeaconLobbyCase>(lobbyCase)
            ..registerSingleton<RoomReadWatermarkStore>(watermarks)
            ..registerSingleton<BeaconThreadsCase>(roomCase)
            ..registerSingleton<BeaconFactCardRepository>(
              FakeBeaconFactCardRepository(),
            )
            ..registerSingleton<CoordinationItemRoomSync>(
              CoordinationItemRoomSync(),
            )
            ..registerSingleton<PresenceRepository>(presenceRepository)
            ..registerSingleton<ImageRepository>(ImageRepository())
            ..registerSingleton<ClipboardImageRepository>(
              ClipboardImageRepository(),
            );

          Widget app(Widget child) => MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: profile),
              BlocProvider<PresenceCubit>.value(value: presence),
              BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              theme: TenturaTheme.light(),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(body: TenturaResponsiveScope(child: child)),
            ),
          );
          await tester.pumpWidget(
            app(
              const BeaconLobbyEntryRow(
                beaconId: _beaconId,
                isAuthor: true,
              ),
            ),
          );
          await _frames(tester);
          expect(find.text('1 new'), findsOneWidget);

          final lobby = BeaconLobbyCubit(
            lobbyCase,
            effects,
            beaconId: _beaconId,
            attention: attention,
          );
          addTearDown(lobby.close);
          await lobby.load();
          await tester.pumpWidget(
            app(
              BlocProvider<BeaconLobbyCubit>.value(
                value: lobby,
                child: const Column(
                  children: [
                    BeaconLobbyEntryRow(beaconId: _beaconId, isAuthor: true),
                    Expanded(child: BeaconLobbyChat()),
                  ],
                ),
              ),
            ),
          );
          await _frames(tester);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          });
          // Recreated alongside the new chat cubit, so agreement is checked
          // after reconstruction as well as before opening Questions.
          expect(find.text('1 new'), findsOneWidget);
          expect(find.byType(RoomMessageTile), findsNWidgets(3));
          expect(find.byType(RoomUnreadDivider), findsOneWidget);
          final divider = find.byType(RoomUnreadDivider);
          final oldQuestion = find.textContaining('Question 2');
          final newQuestion = find.textContaining('Question 3');
          final chat = tester
              .element(find.byType(RoomMessageTile).first)
              .read<RoomCubit>();
          expect(
            (
              count: tester.widget<RoomUnreadDivider>(divider).unreadCount,
              firstUnread: chat.state.unreadBandMessageId,
              belowReadQuestions:
                  tester.getBottomLeft(oldQuestion).dy <
                  tester.getTopLeft(divider).dy,
              aboveNewQuestion:
                  tester.getBottomLeft(divider).dy <=
                  tester.getTopLeft(newQuestion).dy,
            ),
            (
              count: 1,
              firstUnread: 'question-3',
              belowReadQuestions: true,
              aboveNewQuestion: true,
            ),
            reason: 'Overview shows 1 new: mark only Bob’s third question.',
          );
          expect(find.text('Unread · 1'), findsOneWidget);
        },
      );
    }
  });
}
