import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/enums.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  Uri? launchedUserLink;

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {}

  @override
  Future<void> launchUrl(String uri) async {}

  @override
  Future<void> launchUserLink(Uri uri) async {
    launchedUserLink = uri;
  }
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

// Coordination-linked (promoted ask) + empty reactionCounts -- the one
// combination where the bubble registers a touch-only onOpenItem
// TapGestureRecognizer (see _MessageBubbleInteraction) *and* the body renders
// via RoomMessageTextBody's inline-trailing-meta span builder.
RoomMessage _linkedMessage(String body) => RoomMessage(
  id: 'm1',
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: body,
  createdAt: DateTime.utc(2026),
  linkedItemId: 'item1',
  linkedItemKind: CoordinationItemKind.ask.value,
  linkedItemStatus: CoordinationItemStatus.open.value,
  linkedItemCreatorId: 'u1',
  linkedItemCreatedAt: DateTime.utc(2026),
  linkedItemUpdatedAt: DateTime.utc(2026),
  linkedEventKind: CoordinationItemEventKind.created.value,
);

const _logicalSize = Size(360, 600);

Widget _harness(Widget child) {
  return MultiBlocProvider(
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
      home: MediaQuery(
        data: const MediaQueryData(size: _logicalSize),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SizedBox(width: _logicalSize.width, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Bubble always registers a DoubleTapGestureRecognizer (quick-react), so any
/// competing TapGestureRecognizer (bubble's onOpenItem, or a link span's) must
/// wait out the double-tap disambiguation window before it resolves as
/// accepted -- pumpAndSettle alone does not advance past a bare Timer.
Future<void> _tapAndSettle(WidgetTester tester, Offset point) async {
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  late _FakePlatformRepository platform;

  setUp(() async {
    await GetIt.I.reset();
    platform = _FakePlatformRepository();
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets(
    'tapping a link in a coordination-linked message opens the link, '
    'not the coordination item',
    (tester) async {
      CoordinationItem? openedItem;

      await tester.pumpWidget(
        _harness(
          RoomMessageTile(
            message: _linkedMessage('Open https://example.com for details'),
            myProfile: const Profile(id: 'viewer', displayName: 'Me'),
            onToggleReaction: (_, _) async {},
            onOpenCoordinationItem: (item) => openedItem = item,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richTextFinder = find
          .descendant(
            of: find.byType(RoomMessageTextBody),
            matching: find.byType(RichText),
          )
          .first;
      final richText = tester.widget<RichText>(richTextFinder);
      final renderParagraph =
          tester.element(richTextFinder).renderObject! as RenderParagraph;
      final text = richText.text.toPlainText();
      final linkStart = text.indexOf('https://');
      final boxes = renderParagraph.getBoxesForSelection(
        TextSelection(baseOffset: linkStart, extentOffset: linkStart + 1),
      );
      final point = renderParagraph.localToGlobal(
        boxes.first.toRect().center,
      );

      await _tapAndSettle(tester, point);

      expect(platform.launchedUserLink, Uri.parse('https://example.com'));
      expect(openedItem, isNull);
    },
  );

  testWidgets('tapping elsewhere on the bubble still opens the coordination '
      'item', (tester) async {
    CoordinationItem? openedItem;

    await tester.pumpWidget(
      _harness(
        RoomMessageTile(
          message: _linkedMessage('Open https://example.com for details'),
          myProfile: const Profile(id: 'viewer', displayName: 'Me'),
          onToggleReaction: (_, _) async {},
          onOpenCoordinationItem: (item) => openedItem = item,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final richTextFinder = find
        .descendant(
          of: find.byType(RoomMessageTextBody),
          matching: find.byType(RichText),
        )
        .first;
    final renderParagraph =
        tester.element(richTextFinder).renderObject! as RenderParagraph;
    final richText = tester.widget<RichText>(richTextFinder);
    final text = richText.text.toPlainText();
    // "Open " prefix, well before the link -- plain non-link text.
    expect(text.startsWith('Open '), isTrue);
    final boxes = renderParagraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    final point = renderParagraph.localToGlobal(boxes.first.toRect().center);

    await _tapAndSettle(tester, point);

    expect(platform.launchedUserLink, isNull);
    expect(openedItem?.id, 'item1');
  });
}
