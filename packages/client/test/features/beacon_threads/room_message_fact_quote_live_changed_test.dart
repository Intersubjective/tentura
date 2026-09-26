// tentura-617.38 (plan §11 U16): "B quotes the fact → A edits it again → B's
// bubble shows 'Changed since quoted' without a reload."
//
// A fact edit only refreshes the room's fact list (factCard invalidation →
// facts scope); the already-loaded messages, and the QuotedFact.currentSeq
// snapshot they carry, are not refetched. So the bubble has to derive
// "changed since" from the live fact card the room already tracks
// (RoomMessageFactQuote.currentFact), not only from the stale snapshot.
//
// The quoted *text* must still never be replaced by the live wording
// (covered by room_message_fact_quote_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';

const _kSurfaceWidth = 360.0;
const _kQuotedText = 'Meet at the north gate at 9';
const _kLiveText = 'Meet at the south gate at 10';

/// Snapshot as loaded with the message: quoted at revision 2, and the fact
/// was still at revision 2 when the message list was fetched.
QuotedFact _staleQuote() => const QuotedFact(
  factCardId: 'fact-1',
  seq: 2,
  currentSeq: 2,
  status: BeaconFactCardStatusBits.active,
  factText: _kQuotedText,
  pinnedById: 'author-a',
  pinnedByTitle: 'Anna',
);

BeaconFactCard _liveFact({required int revisionSeq, String? factText}) =>
    BeaconFactCard(
      id: 'fact-1',
      beaconId: 'b1',
      factText: factText ?? _kLiveText,
      visibility: BeaconFactCardVisibilityBits.room,
      pinnedBy: 'author-a',
      pinnedByTitle: 'Anna',
      createdAt: DateTime.utc(2026, 9, 20, 12),
      status: BeaconFactCardStatusBits.active,
      revisionSeq: revisionSeq,
      lastEditedBy: 'author-a',
      lastEditedByTitle: 'Anna',
      lastEditedAt: DateTime.utc(2026, 9, 26, 12),
    );

Widget _harness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(_kSurfaceWidth, 600)),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SizedBox(width: _kSurfaceWidth, child: child),
        ),
      ),
    ),
  );
}

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

class _FactCardRepository extends FakeBeaconFactCardRepository {
  List<BeaconFactCard> cards = [];

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async =>
      List<BeaconFactCard>.of(cards);
}

/// B's own message quoting the fact at revision 2.
RoomMessage _quotingMessage() => RoomMessage(
  id: 'm-quote',
  beaconId: kRoomCubitFakeBeaconId,
  authorId: kRoomCubitFakeMyUserId,
  author: const Profile(id: kRoomCubitFakeMyUserId, displayName: 'Boris'),
  body: 'Quoting the meeting point',
  createdAt: DateTime.utc(2026, 9, 26, 10),
  quotedFact: _staleQuote(),
);

void main() {
  testWidgets(
    "live fact past the quoted revision shows 'Changed since quoted' "
    'even when the snapshot currentSeq is stale',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _staleQuote(),
            currentFact: _liveFact(revisionSeq: 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Changed since quoted'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('room-fact-quote-diff')),
        findsOneWidget,
      );
      // Still the quoted snapshot, never the live wording.
      expect(find.textContaining(_kLiveText), findsNothing);
    },
  );

  testWidgets(
    "the bubble flips to 'Changed since quoted' in place when the room's "
    'live fact card advances (no message reload)',
    (tester) async {
      final liveFact = ValueNotifier(_liveFact(revisionSeq: 2));
      addTearDown(liveFact.dispose);

      await tester.pumpWidget(
        _harness(
          ValueListenableBuilder<BeaconFactCard>(
            valueListenable: liveFact,
            builder: (_, fact, _) => RoomMessageFactQuote(
              quotedFact: _staleQuote(),
              currentFact: fact,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Changed since quoted'), findsNothing);

      // A edits the fact again: only the fact list refreshes.
      liveFact.value = _liveFact(revisionSeq: 3);
      await tester.pumpAndSettle();

      expect(find.textContaining('Changed since quoted'), findsOneWidget);
      expect(find.textContaining(_kLiveText), findsNothing);
    },
  );

  testWidgets(
    'live fact still at the quoted revision shows no change line',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          RoomMessageFactQuote(
            quotedFact: _staleQuote(),
            currentFact: _liveFact(revisionSeq: 2, factText: _kQuotedText),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Changed since quoted'), findsNothing);
    },
  );

  testWidgets(
    'a factCard invalidation alone (no message refetch) turns the quoting '
    "RoomMessageTile to 'Changed since quoted'",
    (tester) async {
      await GetIt.I.reset();
      GetIt.I.registerSingleton<PlatformRepositoryPort>(
        _FakePlatformRepository(),
      );
      addTearDown(GetIt.I.reset);
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);

      final fakeRoom = FakeBeaconThreadsRepository(
        userId: kRoomCubitFakeMyUserId,
      )..messages = [_quotingMessage()];
      addTearDown(fakeRoom.dispose);
      final factRepo = _FactCardRepository()
        ..cards = [_liveFact(revisionSeq: 2, factText: _kQuotedText)];

      final cubit = (await tester.runAsync(() async {
        final c = roomCubitForTest(
          fakeRoom,
          beaconRoomCase: BeaconThreadsCase(
            fakeRoom,
            factRepo,
            FakePollingRepository(),
            FakeBeaconRoomHintsRepository(),
            RoomReadWatermarkStore.testing(),
            buildTestRealtimeSync().case_,
            env: const Env(),
            logger: Logger('test'),
          ),
        );
        await awaitRoomCubitLoad(c);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return c;
      }))!;
      addTearDown(cubit.close);
      expect(cubit.state.factCards.single.revisionSeq, 2);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(
              value: GetIt.I<ProfileCubit>(),
            ),
            BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
            BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
            BlocProvider<RoomCubit>.value(value: cubit),
          ],
          child: _harness(
            BlocBuilder<RoomCubit, RoomState>(
              builder: (_, state) => RoomMessageTile(
                message: state.messages.single,
                myProfile: const Profile(
                  id: kRoomCubitFakeMyUserId,
                  displayName: 'Boris',
                ),
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RoomMessageFactQuote), findsOneWidget);
      expect(find.textContaining('Changed since quoted'), findsNothing);

      // A edits the fact again: the server fans out a factCard invalidation.
      final messagesBefore = fakeRoom.fetchMessagesCallCount;
      await tester.runAsync(() async {
        factRepo.cards = [_liveFact(revisionSeq: 3)];
        fakeRoom.emitInvalidation(BeaconRoomEntityType.factCard);
        await cubit.stream.firstWhere(
          (s) => s.factCards.any((f) => f.revisionSeq == 3),
        );
      });
      await tester.pumpAndSettle();

      expect(
        fakeRoom.fetchMessagesCallCount,
        messagesBefore,
        reason: 'the fact edit must not reload the message page',
      );
      expect(find.textContaining('Changed since quoted'), findsOneWidget);
      // The bubble keeps the quoted-at-send snapshot.
      expect(find.textContaining(_kQuotedText), findsOneWidget);
      expect(find.textContaining(_kLiveText), findsNothing);
    },
  );
}
