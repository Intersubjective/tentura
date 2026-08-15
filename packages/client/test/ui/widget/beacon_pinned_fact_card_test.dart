import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart'
    show BeaconRoomMessageAttachmentKind;
import 'package:tentura/features/beacon_view/ui/widget/beacon_pinned_fact_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

BeaconFactCard _fact({
  required String id,
  String text = '',
  List<RoomMessageAttachment> attachments = const [],
}) =>
    BeaconFactCard(
      id: id,
      beaconId: 'b1',
      factText: text,
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'u1',
      createdAt: DateTime.utc(2025),
      status: BeaconFactCardStatusBits.active,
      attachments: attachments,
    );

RoomMessageAttachment _image(String id) => RoomMessageAttachment(
      id: id,
      kind: BeaconRoomMessageAttachmentKind.image,
      position: 0,
      mime: 'image/jpeg',
      sizeBytes: 1,
      imageId: 'img-$id',
      imageAuthorId: 'auth',
    );

Widget _harness({
  required BeaconFactCard fact,
  bool isNew = false,
  TargetPlatform? platform,
  VoidCallback? onManage,
  bool showPointerManage = false,
}) {
  return MaterialApp(
    theme: TenturaTheme.light().copyWith(
      platform: platform ?? TargetPlatform.android,
    ),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: TenturaResponsiveScope(
      child: Scaffold(
        body: Builder(
          builder: (context) => BeaconPinnedFactCard(
            fact: fact,
            l10n: L10n.of(context)!,
            isNew: isNew,
            onManage: onManage,
            showPointerManage: showPointerManage,
          ),
        ),
      ),
    ),
  );
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

  testWidgets('fact text link opens URL', (tester) async {
    await tester.pumpWidget(
      _harness(
        fact: _fact(
          id: 'f1',
          text: 'Check https://example.com for details.',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);

    final richTextFinder = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('https://'),
    );
    final richText = tester.widget<RichText>(richTextFinder);
    final renderParagraph =
        tester.element(richTextFinder).renderObject! as RenderParagraph;
    final text = richText.text.toPlainText();
    final linkStart = text.indexOf('https://');
    final boxes = renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: linkStart, extentOffset: linkStart + 1),
    );
    final point = renderParagraph.localToGlobal(boxes.first.toRect().center);

    await tester.tapAt(point);
    await tester.pumpAndSettle();

    expect(platform.launchedUserLink, Uri.parse('https://example.com'));
  });

  testWidgets('plain fact text still renders', (tester) async {
    await tester.pumpWidget(
      _harness(fact: _fact(id: 'f1', text: 'No links in this one.')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No links in this one'), findsOneWidget);
  });

  testWidgets('public fact card shows visibility mark', (tester) async {
    await tester.pumpWidget(
      _harness(fact: _fact(id: 'f1', text: 'Public pinned fact')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Public'), findsOneWidget);
    expect(find.byIcon(Icons.public_outlined), findsOneWidget);
  });

  testWidgets('new badge renders without RoomCubit', (tester) async {
    await tester.pumpWidget(
      _harness(
        fact: _fact(id: 'f1', text: 'Fresh fact'),
        isNew: true,
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await L10n.delegate.load(const Locale('en'));
    expect(find.text(l10n.beaconPinnedFactNewBadge), findsOneWidget);
  });

  testWidgets('multi-image fact shows page indicator', (tester) async {
    await tester.pumpWidget(
      _harness(
        fact: _fact(
          id: 'f1',
          attachments: [_image('a'), _image('b')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('multi-image fact nav advances inline gallery', (tester) async {
    await tester.pumpWidget(
      _harness(
        fact: _fact(
          id: 'f1',
          attachments: [_image('a'), _image('b')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('macOS theme wraps fact text in SelectionArea', (tester) async {
    await tester.pumpWidget(
      _harness(
        fact: _fact(id: 'f1', text: 'Gate code is 4821'),
        platform: TargetPlatform.macOS,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  Future<void> hoverCard(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(BeaconPinnedFactCard));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(center);
    await tester.pumpAndSettle();
  }

  testWidgets('hover more is hidden until pointer hover', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    var manages = 0;
    await tester.pumpWidget(
      _harness(
        fact: _fact(id: 'f1', text: 'Hover me'),
        onManage: () => manages++,
        showPointerManage: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip(l10n.beaconRoomFactManageSheetTitle), findsNothing);

    await hoverCard(tester);

    expect(find.byTooltip(l10n.beaconRoomFactManageSheetTitle), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.beaconRoomFactManageSheetTitle));
    expect(manages, 1);
  });

  testWidgets('hover more stays hidden without showPointerManage', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      _harness(
        fact: _fact(id: 'f1', text: 'Viewer fact'),
        onManage: () {},
      ),
    );
    await tester.pumpAndSettle();
    await hoverCard(tester);

    expect(find.byTooltip(l10n.beaconRoomFactManageSheetTitle), findsNothing);
  });

  testWidgets('long-press still manages without hover', (tester) async {
    var manages = 0;
    await tester.pumpWidget(
      _harness(
        fact: _fact(id: 'f1', text: 'Press me'),
        onManage: () => manages++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(BeaconPinnedFactCard));
    await tester.pumpAndSettle();
    expect(manages, 1);
  });
}
