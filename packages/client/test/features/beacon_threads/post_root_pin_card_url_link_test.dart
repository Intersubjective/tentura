import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';
import 'package:tentura/features/beacon_threads/ui/widget/post_root_pin_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import 'support/room_body_harness.dart';

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

const _author = Profile(id: 'Uauthor', displayName: 'Олег');
const _postId = 'Bpost1126001';
const _rootId = 'Mroot1126001';

RoomMessage _rootWithUrl(String body) => RoomMessage(
  id: _rootId,
  beaconId: _postId,
  authorId: _author.id,
  author: _author,
  body: body,
  createdAt: DateTime.utc(2026, 11, 1, 12),
);

Widget _pinHarness({
  required RoomMessage root,
  Locale locale = const Locale('en'),
  double width = 390,
}) {
  final pin = RoomPostRootPin(
    messageId: root.id,
    excerpt: root.body,
    startedBy: _author.displayName,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 720)),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: PostRootPinCard(
                pin: pin,
                collapsed: false,
                onTap: () {},
                now: DateTime.utc(2026, 11, 1, 13),
                rootMessage: root,
                author: _author,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _tapLinkInPostRoot(WidgetTester tester) async {
  final richTextFinder = find
      .descendant(
        of: find.byKey(const Key('PostRootPinCard.expanded')),
        matching: find.descendant(
          of: find.byType(RoomMessageTextBody),
          matching: find.byType(RichText),
        ),
      )
      .first;
  final richText = tester.widget<RichText>(richTextFinder);
  final renderParagraph =
      tester.element(richTextFinder).renderObject! as RenderParagraph;
  final text = richText.text.toPlainText();
  final linkStart = text.indexOf('https://');
  expect(linkStart, greaterThanOrEqualTo(0));
  final boxes = renderParagraph.getBoxesForSelection(
    TextSelection(baseOffset: linkStart, extentOffset: linkStart + 1),
  );
  final point = renderParagraph.localToGlobal(boxes.first.toRect().center);
  await tester.tapAt(point);
  await tester.pump();
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

  testWidgets('tapping a URL in the expanded Post root opens launchUserLink', (
    tester,
  ) async {
    const url = 'https://example.com/details';
    await tester.pumpWidget(
      _pinHarness(root: _rootWithUrl('See $url for more')),
    );
    await tester.pumpAndSettle();

    await _tapLinkInPostRoot(tester);

    expect(platform.launchedUserLink, Uri.parse(url));
  });

  testWidgets('375×667 RU: long Post-root URL wraps and stays tappable', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    const url =
        'https://intersubjective.space/docs/tentura/posts/очень-длинный-путь';
    const prefix = 'Ссылка: ';
    const body = '$prefix$url — напишите, если сможете.';
    await tester.pumpWidget(
      _pinHarness(
        root: _rootWithUrl(body),
        locale: const Locale('ru'),
        width: 375,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(url, findRichText: true), findsOneWidget);
    expect(find.textContaining(prefix, findRichText: true), findsOneWidget);

    await _tapLinkInPostRoot(tester);
    expect(platform.launchedUserLink?.toString(), startsWith('https://'));
  });

  testWidgets('Post room expanded card link tap through BeaconRoomBody', (
    tester,
  ) async {
    const url = 'https://docs.example.com/post-root';
    final root = _rootWithUrl('Docs: $url');
    final state = RoomState(
      beaconId: _postId,
      myUserId: 'Ureader',
      messages: [root],
      participantsLoaded: true,
      beaconAuthorId: _author.id,
      beaconStatus: BeaconStatus.open,
      firstLoadDone: true,
    );
    await pumpBeaconRoomBody(
      tester,
      roomState: state,
      capabilities: const RoomCapabilities.post(),
      postRoot: RoomPostRootPin(
        messageId: root.id,
        excerpt: root.body,
        startedBy: _author.displayName,
      ),
      beaconAuthorId: _author.id,
      beaconAuthor: _author,
      width: 375,
      height: 667,
    );
    GetIt.I.registerSingleton<PlatformRepositoryPort>(platform);
    await pumpUntilViewportDone(tester);

    expect(find.byKey(const Key('PostRootPinCard.expanded')), findsOneWidget);
    await _tapLinkInPostRoot(tester);
    expect(platform.launchedUserLink, Uri.parse(url));
  });
}
