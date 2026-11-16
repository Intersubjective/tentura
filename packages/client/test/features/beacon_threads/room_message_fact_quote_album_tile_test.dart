// A quoted fact's photos inside a real chat bubble (RoomMessageTile): same
// album widget as a direct album message, and a layout that fits the bubble
// on a phone and on a desktop surface.

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/components/room_message_bubble_shape.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_fact_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {}
}

class _MockProfileCubit extends Mock implements ProfileCubit {
  @override
  ProfileState get state => const ProfileState(
    profile: Profile(id: 'viewer', displayName: 'Me'),
  );

  @override
  Stream<ProfileState> get stream => Stream<ProfileState>.value(state);
}

class _MockPresenceCubit extends Mock implements PresenceCubit {
  @override
  Map<String, UserPresenceStatus> get state => const {};

  @override
  Stream<Map<String, UserPresenceStatus>> get stream =>
      Stream<Map<String, UserPresenceStatus>>.value(state);
}

List<RoomMessageAttachment> _images(int n, String prefix) => [
  for (var i = 0; i < n; i++)
    RoomMessageAttachment(
      id: '$prefix$i',
      kind: BeaconRoomMessageAttachmentKind.image,
      position: i,
      mime: 'image/jpeg',
      sizeBytes: 1,
      imageId: '$prefix-img-$i',
      imageAuthorId: 'u1',
    ),
];

RoomMessage _message({List<RoomMessageAttachment> own = const []}) =>
    RoomMessage(
      id: 'm1',
      beaconId: 'b1',
      authorId: 'u1',
      author: const Profile(id: 'u1', displayName: 'Author'),
      body: 'Check the pinned fact above',
      createdAt: DateTime.utc(2026),
      attachments: own,
      quotedFact: QuotedFact(
        factCardId: 'fact-1',
        seq: 1,
        currentSeq: 1,
        status: BeaconFactCardStatusBits.active,
        factText: 'The venue moved to 221B Baker Street',
        pinnedById: 'peer-1',
        pinnedByTitle: 'Peer One',
        attachments: _images(3, 'q'),
      ),
    );

Future<void> _pumpTile(
  WidgetTester tester,
  Size size,
  RoomMessage message,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ProfileCubit>.value(value: _MockProfileCubit()),
        BlocProvider<PresenceCubit>.value(value: _MockPresenceCubit()),
        BlocProvider<ScreenCubit>(create: (_) => ScreenCubit.local()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: RoomMessageTile(
                message: message,
                myProfile: const Profile(id: 'viewer', displayName: 'Me'),
                onToggleReaction: (_, _) async {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder get _quoteAlbum => find.descendant(
  of: find.byType(RoomMessageFactQuote),
  matching: find.byType(RoomMessageInlineImageAlbum),
);

/// The message bubble's own container (nearest Material with the bubble
/// shape around the quote).
Finder get _bubble => find.ancestor(
  of: find.byType(RoomMessageFactQuote),
  matching: find.byWidgetPredicate(
    (w) => w is Material && w.shape is RoomMessageBubbleShape,
  ),
);

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(
      _FakePlatformRepository(),
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final (name, size) in [
    ('phone 375x667', const Size(375, 667)),
    ('desktop 1280x800', const Size(1280, 800)),
  ]) {
    testWidgets('quoted 3-image album lays out inside the bubble on $name', (
      tester,
    ) async {
      await _pumpTile(tester, size, _message());
      expect(tester.takeException(), isNull);
      expect(_quoteAlbum, findsOneWidget);
      final bubble = tester.getRect(_bubble.first);
      final album = tester.getRect(_quoteAlbum);
      expect(album.width, greaterThan(0));
      expect(album.left, greaterThanOrEqualTo(bubble.left));
      expect(album.right, lessThanOrEqualTo(bubble.right));
      expect(
        find.descendant(
          of: _quoteAlbum,
          matching: find.text('1/3'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping a quoted photo opens the viewer and leaves the quote '
        'collapsed on $name', (tester) async {
      await _pumpTile(tester, size, _message());
      await tester.tap(
        find.descendant(of: _quoteAlbum, matching: find.byType(Image)).first,
      );
      // The bubble's double-tap (quick react) holds a single tap back for
      // kDoubleTapTimeout before the photo's own tap wins.
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      final gallery = find.byType(RoomAttachmentFullscreenGallery);
      expect(gallery, findsOneWidget);
      expect(
        tester.widget<RoomAttachmentFullscreenGallery>(gallery).initialIndex,
        0,
      );
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(gallery, findsNothing);
      expect(find.text('Open'), findsNothing);
      expect(find.textContaining('The venue moved'), findsOneWidget);
    });
  }

  testWidgets('a quoted-fact album and a direct album in one bubble are the '
      'same album widget', (tester) async {
    await _pumpTile(
      tester,
      const Size(375, 667),
      _message(own: _images(2, 'd')),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(RoomMessageInlineImageAlbum), findsNWidgets(2));
    expect(_quoteAlbum, findsOneWidget);
  });
}
