import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_owner_summary.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_child_promotion_footer.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../features/beacon_create/fake_beacon_ports.dart';

class _TestProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'me', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _TestPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

void main() {
  const me = Profile(id: 'me', displayName: 'Me');
  const vadim = Profile(id: 'vadim', displayName: 'Vadim');
  const bob = Profile(id: 'bob', displayName: 'Bob');
  final base = DateTime.utc(2026, 9, 14, 12);

  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  void registerHierarchy({required String title}) {
    final port = FakeBeaconHierarchyRepositoryPort()
      ..childPreviews['child-1'] = BeaconHierarchySummary(
        beaconId: 'child-1',
        title: title,
        owner: const BeaconHierarchyOwnerSummary(
          id: 'author-1',
          displayName: 'Alice',
        ),
        status: BeaconStatus.open,
        publishedAt: DateTime.utc(2026, 9, 14),
        isTombstone: false,
      );
    GetIt.I.registerSingleton<BeaconHierarchyCase>(
      buildBeaconHierarchyCaseForTest(
        port,
        createCase: BeaconCreateCase(
          FakeBeaconWritePort(),
          FakeBeaconImagePort(),
        ),
        beacons: FakeBeaconWritePort(),
        commandStore: InMemoryBeaconChildCommandStore(),
      ),
    );
  }

  Future<void> pumpChat(
    WidgetTester tester, {
    required List<RoomMessage> messages,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ProfileCubit>.value(value: _TestProfileCubit()),
          BlocProvider<PresenceCubit>.value(value: _TestPresenceCubit()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BasicChatBody(
                  messages: messages,
                  myProfile: me,
                  participants: const [],
                  isLoading: false,
                  enableComposerAttachments: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'issue #170: reply after promotion still reads as reply to Vadim, '
    'with no request card between source and reply',
    (tester) async {
      registerHierarchy(title: 'Spare laptop for workshop');

      final source = RoomMessage(
        id: 'source-1',
        beaconId: 'b1',
        authorId: vadim.id,
        author: vadim,
        body: 'Need a spare laptop for the workshop tomorrow.',
        createdAt: base,
      );
      final notice = RoomMessage(
        id: 'notice-1',
        beaconId: 'b1',
        authorId: 'promoter',
        author: const Profile(id: 'promoter', displayName: 'Promoter'),
        body: '',
        createdAt: base.add(const Duration(minutes: 1)),
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        systemPayloadJson: jsonEncode({
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
          'sourceMessageId': 'source-1',
        }),
      );
      final reply = RoomMessage(
        id: 'reply-1',
        beaconId: 'b1',
        authorId: bob.id,
        author: bob,
        body: 'I can bring one.',
        createdAt: base.add(const Duration(minutes: 3)),
        replyToMessageId: 'source-1',
        replyToAuthorId: vadim.id,
        replyToAuthorTitle: 'Vadim',
        replyToBodyExcerpt: 'Need a spare laptop for the workshop tomorrow.',
      );

      await pumpChat(tester, messages: [source, notice, reply]);

      // Sibling notice is deduped when source is on-page.
      expect(find.byType(BeaconHierarchyNotice), findsNothing);
      // Compact source footer, not a Chat request card.
      expect(find.byType(BeaconChildPromotionFooter), findsOneWidget);
      expect(find.byType(BeaconCardShell), findsNothing);
      // Source + reply tiles (notice filtered out).
      expect(find.byType(RoomMessageTile), findsNWidgets(2));
      // Reply ownership is the quote of Vadim.
      expect(find.byType(RoomMessageReplyQuote), findsOneWidget);
      expect(find.text('Vadim'), findsWidgets);
      expect(find.text('Spare laptop for workshop'), findsOneWidget);
      // Reply body is present (inline meta path uses RoomMessageTextBody).
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RoomMessageTextBody && w.display == 'I can bring one.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'direct-create childCreated notice is centered chrome without a card',
    (tester) async {
      registerHierarchy(title: 'Direct child');

      final notice = RoomMessage(
        id: 'notice-direct',
        beaconId: 'b1',
        authorId: 'promoter',
        author: const Profile(id: 'promoter', displayName: 'Promoter'),
        body: '',
        createdAt: base,
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        systemPayloadJson: jsonEncode({
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
          // no sourceMessageId — direct create
        }),
      );
      final later = RoomMessage(
        id: 'later-1',
        beaconId: 'b1',
        authorId: bob.id,
        author: bob,
        body: 'Nice.',
        createdAt: base.add(const Duration(minutes: 2)),
      );

      await pumpChat(tester, messages: [notice, later]);

      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(
        find.text(l10n.beaconHierarchyNoticeChildCreated),
        findsOneWidget,
      );
      expect(find.byType(BeaconHierarchyNotice), findsOneWidget);
      expect(find.byType(BeaconChildPromotionFooter), findsNothing);
      expect(find.byType(BeaconCardShell), findsNothing);
      expect(find.byType(RoomMessageTile), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (w) => w is RoomMessageTextBody && w.display == 'Nice.',
        ),
        findsOneWidget,
      );
    },
  );
}
