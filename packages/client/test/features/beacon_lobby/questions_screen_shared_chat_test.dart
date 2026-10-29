// The Questions screen is the shared Request/Post chat on its own thread
// (#726): the same message tiles, reply-to-message instead of a separate
// answer feature, posts that go to the Questions thread, and the viewer's
// read-only reason as the hint of a disabled composer. The old Questions
// list, composer and tile are gone.

import 'package:tentura/domain/attention/attention_case.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../beacon_threads/room_cubit_fakes.dart';
import '../beacon_threads/support/room_body_harness.dart'
    show RoomBodyHarnessPresenceCubit, RoomBodyHarnessProfileCubit;
import 'fake_lobby_port.dart';
import '../my_work/my_work_test_support.dart' show buildStubAttentionCase;

const _beaconId = 'B1';

/// What [FakeLobbyPort.open] answers as the Questions id.
const _lobbyId = 'Llobby';

const _nina = Profile(id: 'Unina', displayName: 'Nina');
const _anna = Profile(id: 'Uauthor', displayName: 'Anna');

final _at = DateTime.utc(2026, 10, 1, 12);

RoomMessage _questionsMessage(
  String id, {
  required Profile author,
  required String body,
  required DateTime createdAt,
}) => RoomMessage(
  id: id,
  beaconId: _beaconId,
  authorId: author.id,
  author: author,
  body: body,
  createdAt: createdAt,
  threadItemId: _lobbyId,
);

/// The room API as the server serves Questions to someone outside the
/// Request's room: only the Questions thread is listed, a create lands in
/// the thread it names (with the reply snapshot of its target), and the
/// participant list is refused.
class _QuestionsRoomRepository extends FakeBeaconThreadsRepository {
  _QuestionsRoomRepository() : super(userId: _nina.id);

  final createdThreadItemIds = <String?>[];

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) async {
    fetchMessagesCallCount++;
    await fetchMessagesCompleter?.future;
    return [
      for (final m in messages)
        if (m.threadItemId == threadItemId) m,
    ];
  }

  @override
  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) async {
    fetchParticipantsCallCount++;
    throw StateError('participants are refused outside the room');
  }

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    String? clientMessageId,
  }) async {
    createMessageCalls++;
    lastReplyToMessageId = replyToMessageId;
    createdThreadItemIds.add(threadItemId);
    final target = replyToMessageId == null
        ? null
        : messages.where((m) => m.id == replyToMessageId).firstOrNull;
    final id = 'Mcreated$createMessageCalls';
    messages = [
      ...messages,
      RoomMessage(
        id: id,
        beaconId: beaconId,
        authorId: _nina.id,
        author: _nina,
        body: body,
        createdAt: _at.add(Duration(hours: 1, minutes: createMessageCalls)),
        threadItemId: threadItemId,
        replyToMessageId: target?.id,
        replyToAuthorId: target?.authorId,
        replyToAuthorTitle: target?.author.displayName,
        replyToBodyExcerpt: target?.body,
      ),
    ];
    return id;
  }
}

class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: BeaconLobbyRoute.page, initial: true),
  ];
}

Future<void> _pumpFrames(WidgetTester tester, [int frames = 30]) async {
  // Bounded: the chat surface hosts animations that never settle.
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the Questions screen of [_beaconId] as [_nina], through its route,
/// over the real Questions and room use cases fed by [lobby] and [room].
Future<void> _openQuestions(
  WidgetTester tester, {
  required FakeLobbyPort lobby,
  required _QuestionsRoomRepository room,
}) async {
  tester.view.physicalSize = const Size(700, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final getIt = GetIt.I;
  await getIt.reset();
  addTearDown(getIt.reset);

  final effects = RecordingEffects();
  final profileCubit = RoomBodyHarnessProfileCubit(_nina);
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<PresenceCubit>(presenceCubit)
    ..registerSingleton<AttentionCase>(buildStubAttentionCase())
    ..registerSingleton<UiEffectPort>(effects)
    ..registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(lobby, FakeRealtimeSyncPort()),
    )
    ..registerSingleton<BeaconThreadsCase>(roomCubitMakeCase(room))
    ..registerSingleton<BeaconFactCardRepository>(
      FakeBeaconFactCardRepository(),
    )
    ..registerSingleton<CoordinationItemRoomSync>(CoordinationItemRoomSync())
    ..registerSingleton<PresenceRepository>(roomCubitFakePresenceRepository())
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());

  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit(effects)),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) =>
            TenturaResponsiveScope(child: child ?? const SizedBox.shrink()),
        routerConfig: router.config(
          deepLinkBuilder: (_) =>
              DeepLink([BeaconLobbyRoute(beaconId: _beaconId)]),
        ),
      ),
    ),
  );
  await _pumpFrames(tester);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

/// The shared chat composer.
Finder get _composer => find.byKey(TestIds.key(TestIds.roomMessageInput));

/// Anything still built from the old Questions body (deleted with #726, so
/// matched by name rather than imported).
Finder get _oldQuestionsBody => find.byWidgetPredicate(
  (w) => w.runtimeType.toString() == 'BeaconLobbyBody',
);

Future<void> _replyTo(WidgetTester tester, String body) async {
  final text = find.descendant(
    of: find.ancestor(
      of: find.textContaining(body),
      matching: find.byType(RoomMessageTile),
    ),
    matching: find.byWidgetPredicate(
      (w) => w is RoomMessageTextBody || w is ShowMoreText,
    ),
  );
  expect(text, findsWidgets, reason: 'the message "$body" as a chat tile');
  await tester.longPressAt(tester.getTopLeft(text.first) + const Offset(8, 8));
  await _pumpFrames(tester, 10);
  final l10n = lookupL10n(const Locale('en'));
  await tester.tap(find.text(l10n.beaconRoomActionReply).last);
  await _pumpFrames(tester, 10);
}

void main() {
  final l10n = lookupL10n(const Locale('en'));

  group('Questions screen renders the shared chat', () {
    testWidgets(
      'empty Questions survive inactive and leaving during completion',
      (
        tester,
      ) async {
        final lobby = FakeLobbyPort(viewerId: _nina.id);
        final room = _QuestionsRoomRepository();
        await _openQuestions(tester, lobby: lobby, room: room);

        expect(find.byKey(const Key('beaconRoomEmptyState')), findsOneWidget);
        expect(find.byType(RoomMessageTile), findsNothing);
        expect(_composer, findsOneWidget);
        expect(tester.takeException(), isNull);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await _pumpFrames(tester, 2);
        expect(find.byKey(const Key('beaconRoomEmptyState')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester, 2);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'leaving Questions before its empty response completes is safe',
      (
        tester,
      ) async {
        final completion = Completer<void>();
        final room = _QuestionsRoomRepository()
          ..fetchMessagesCompleter = completion;
        await _openQuestions(
          tester,
          lobby: FakeLobbyPort(viewerId: _nina.id),
          room: room,
        );
        expect(room.fetchMessagesCallCount, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        completion.complete();
        await _pumpFrames(tester, 4);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('messages are shared room message tiles, not the old '
        'Questions list', (tester) async {
      final lobby = FakeLobbyPort(viewerId: _nina.id);
      final room = _QuestionsRoomRepository()
        ..messages = [
          _questionsMessage(
            'M1',
            author: _nina,
            body: 'Which Saturday?',
            createdAt: _at,
          ),
          _questionsMessage(
            'M2',
            author: _anna,
            body: 'The 18th',
            createdAt: _at.add(const Duration(minutes: 5)),
          ),
        ];
      await _openQuestions(tester, lobby: lobby, room: room);

      expect(_oldQuestionsBody, findsNothing);
      expect(find.byType(RoomMessageTile), findsNWidgets(2));
      for (final body in ['Which Saturday?', 'The 18th']) {
        expect(
          find.descendant(
            of: find.byType(RoomMessageTile),
            matching: find.textContaining(body),
          ),
          findsWidgets,
          reason: body,
        );
      }
      expect(_composer, findsOneWidget);
    });

    testWidgets("the Request author's messages carry the Author mark; "
        "another sender's do not", (tester) async {
      const omar = Profile(id: 'Uomar', displayName: 'Omar');
      final lobby = FakeLobbyPort(viewerId: _nina.id);
      final room = _QuestionsRoomRepository()
        ..messages = [
          _questionsMessage(
            'M1',
            author: omar,
            body: 'Is there parking?',
            createdAt: _at,
          ),
          _questionsMessage(
            'M2',
            author: _anna,
            body: 'Yes, behind the hall',
            createdAt: _at.add(const Duration(minutes: 5)),
          ),
        ];
      await _openQuestions(tester, lobby: lobby, room: room);

      Finder tileOf(String body) => find.ancestor(
        of: find.textContaining(body),
        matching: find.byType(RoomMessageTile),
      );
      final mark = find.text(l10n.beaconLobbyAuthorBadge.toUpperCase());
      expect(
        find.descendant(of: tileOf('Yes, behind the hall'), matching: mark),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tileOf('Is there parking?'), matching: mark),
        findsNothing,
      );
    });

    testWidgets('a reply to a question shows the quote of that question', (
      tester,
    ) async {
      final lobby = FakeLobbyPort(viewerId: _nina.id);
      final room = _QuestionsRoomRepository()
        ..messages = [
          _questionsMessage(
            'M1',
            author: _anna,
            body: 'Bring your own gloves',
            createdAt: _at,
          ),
        ];
      await _openQuestions(tester, lobby: lobby, room: room);

      await _replyTo(tester, 'Bring your own gloves');
      await tester.enterText(_composer, 'What size?');
      await tester.tap(find.byTooltip(l10n.tooltipSendMessage));
      await _pumpFrames(tester);

      expect(room.lastReplyToMessageId, 'M1');
      expect(room.createdThreadItemIds, [_lobbyId]);
      final replyTile = find.ancestor(
        of: find.textContaining('What size?'),
        matching: find.byType(RoomMessageTile),
      );
      expect(replyTile, findsWidgets);
      expect(
        find.descendant(
          of: replyTile.first,
          matching: find.byType(RoomMessageReplyQuote),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.descendant(
            of: replyTile.first,
            matching: find.byType(RoomMessageReplyQuote),
          ),
          matching: find.textContaining('Bring your own gloves'),
        ),
        findsWidgets,
      );
    });

    testWidgets('sending posts into the Questions thread', (tester) async {
      final lobby = FakeLobbyPort(viewerId: _nina.id);
      final room = _QuestionsRoomRepository();
      await _openQuestions(tester, lobby: lobby, room: room);

      expect(_composer, findsOneWidget);
      await tester.enterText(_composer, 'How many boxes?');
      await tester.tap(find.byTooltip(l10n.tooltipSendMessage));
      await _pumpFrames(tester);

      expect(room.createdThreadItemIds, [_lobbyId]);
      expect(
        find.descendant(
          of: find.byType(RoomMessageTile),
          matching: find.textContaining('How many boxes?'),
        ),
        findsWidgets,
      );
      // Not through the old Questions post operation.
      expect(lobby.calls.where((c) => c.startsWith('post ')), isEmpty);
    });
  });

  group('Questions read-only reason is the hint of a disabled composer', () {
    for (final (reason, hint) in [
      (BeaconLobbyLimitReason.closed, l10n.beaconLobbyReadOnlyClosed),
      (BeaconLobbyLimitReason.withdrew, l10n.beaconLobbyReadOnlyWithdrew),
      (BeaconLobbyLimitReason.removed, l10n.beaconLobbyReadOnly),
    ]) {
      testWidgets('read-only because ${reason.name}', (tester) async {
        final lobby = FakeLobbyPort(viewerId: _nina.id)
          ..canPost = false
          ..limitReason = reason;
        final room = _QuestionsRoomRepository()
          ..messages = [
            _questionsMessage(
              'M1',
              author: _anna,
              body: 'The 18th',
              createdAt: _at,
            ),
          ];
        await _openQuestions(tester, lobby: lobby, room: room);

        expect(_oldQuestionsBody, findsNothing);
        expect(find.byType(RoomMessageTile), findsOneWidget);
        expect(_composer, findsOneWidget);
        final field = tester.widget<TextField>(_composer);
        expect(field.enabled, isFalse);
        expect(field.decoration?.hintText, hint);
      });
    }
  });
}
