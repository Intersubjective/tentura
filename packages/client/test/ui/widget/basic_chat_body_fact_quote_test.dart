import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/image_picked.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

/// Filling all [kMaxRoomMessageAttachments] slots in one `Photos` tap so
/// menu-disabled-state tests don't need to loop the picker.
class _FakeFullImageRepository extends Fake implements ImageRepository {
  @override
  Future<List<ImagePicked>> pickMultipleImages() async => List.generate(
    kMaxRoomMessageAttachments,
    (i) => ImagePicked(
      bytes: Uint8List.fromList([i]),
      fileName: 'test$i.png',
    ),
  );
}

class _FakeClipboardImageRepository extends Fake
    implements ClipboardImageRepository {
  @override
  Future<ClipboardImageReadResult> readImage() async =>
      const ClipboardImageReadResult.notFound();
}

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

final _factCard = BeaconFactCard(
  id: 'fact-1',
  beaconId: 'b1',
  factText: 'The venue moved to 221B Baker Street',
  visibility: BeaconFactCardVisibilityBits.room,
  pinnedBy: 'peer-1',
  pinnedByTitle: 'Peer One',
  createdAt: DateTime.utc(2026, 6, 30, 12),
  status: BeaconFactCardStatusBits.active,
);

void main() {
  Future<void> pumpBody(
    WidgetTester tester, {
    VoidCallback? onPickFact,
    BeaconFactCard? pendingQuotedFact,
    VoidCallback? onCancelQuotedFact,
    RoomMessage? replyTarget,
    VoidCallback? onCancelReply,
    ImageRepository? imageRepository,
    double width = 1400,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 720));
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
            data: MediaQueryData(size: Size(width, 720)),
            child: TenturaResponsiveScope(
              child: Scaffold(
                body: BasicChatBody(
                  messages: const [],
                  myProfile: const Profile(id: 'me', displayName: 'Me'),
                  participants: const [],
                  isLoading: false,
                  imageRepository:
                      imageRepository ?? _FakeFullImageRepository(),
                  clipboardImageRepository: _FakeClipboardImageRepository(),
                  enableComposerAttachments: true,
                  enableParticipantMentions: false,
                  onSend: (body, uploads) async => true,
                  onToggleReaction: (_, _) async {},
                  replyTarget: replyTarget,
                  onCancelReply: onCancelReply,
                  onPickFact: onPickFact,
                  pendingQuotedFact: pendingQuotedFact,
                  onCancelQuotedFact: onCancelQuotedFact,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'attach menu stays enabled and Images/Files are disabled once slots are exhausted',
    (tester) async {
      await pumpBody(tester);

      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('attach')),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, 'Photos'),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, 'Files'),
            )
            .enabled,
        isFalse,
      );
    },
  );

  testWidgets('attach menu has no Fact item when onPickFact is null', (
    tester,
  ) async {
    await pumpBody(tester);

    await tester.tap(find.byKey(const ValueKey('attach')));
    await tester.pumpAndSettle();

    expect(find.text('Fact'), findsNothing);
  });

  testWidgets('tapping the Fact menu item calls onPickFact', (tester) async {
    var picked = false;
    await pumpBody(tester, onPickFact: () => picked = true);

    await tester.tap(find.byKey(const ValueKey('attach')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fact'));
    await tester.pumpAndSettle();

    expect(picked, isTrue);
  });

  testWidgets(
    'pendingQuotedFact shows a banner with pinner and excerpt; close calls onCancelQuotedFact',
    (tester) async {
      var cancelled = false;
      await pumpBody(
        tester,
        pendingQuotedFact: _factCard,
        onCancelQuotedFact: () => cancelled = true,
      );

      expect(find.byKey(const ValueKey('quoted-fact-banner')), findsOneWidget);
      expect(find.textContaining(_factCard.pinnedByTitle), findsOneWidget);
      expect(find.textContaining(_factCard.factText), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quoted-fact-close')));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    },
  );

  testWidgets('reply banner and fact banner render together', (
    tester,
  ) async {
    final replyTarget = RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: 'other',
      author: const Profile(id: 'other', displayName: 'Alex'),
      body: 'Original message body',
      createdAt: DateTime.utc(2026, 6, 30, 12),
    );

    await pumpBody(
      tester,
      replyTarget: replyTarget,
      pendingQuotedFact: _factCard,
    );

    expect(find.text('Reply to Alex'), findsOneWidget);
    expect(find.byKey(const ValueKey('quoted-fact-banner')), findsOneWidget);
    expect(find.textContaining(_factCard.pinnedByTitle), findsOneWidget);
  });

  testWidgets(
    'send fires onSend with empty text when a fact quote is pending',
    (tester) async {
      var sendCalls = 0;
      String? sentBody;

      await tester.binding.setSurfaceSize(const Size(1400, 720));
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
              data: const MediaQueryData(size: Size(1400, 720)),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: BasicChatBody(
                    messages: const [],
                    myProfile: const Profile(id: 'me', displayName: 'Me'),
                    participants: const [],
                    isLoading: false,
                    imageRepository: _FakeFullImageRepository(),
                    clipboardImageRepository: _FakeClipboardImageRepository(),
                    enableComposerAttachments: true,
                    enableParticipantMentions: false,
                    onSend: (body, uploads) async {
                      sendCalls++;
                      sentBody = body;
                      return true;
                    },
                    onToggleReaction: (_, _) async {},
                    pendingQuotedFact: _factCard,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sendCalls, 1);
      expect(sentBody, isEmpty);
    },
  );
}
