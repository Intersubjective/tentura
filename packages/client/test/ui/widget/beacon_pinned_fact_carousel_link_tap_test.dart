import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_pinned_fact_carousel.dart';

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

BeaconFactCard _fact(String text) => BeaconFactCard(
  id: 'f1',
  beaconId: 'b1',
  factText: text,
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'u1',
  createdAt: DateTime.utc(2025),
  status: BeaconFactCardStatusBits.active,
);

// Filler pushing raw content height past the default 280px page budget, so
// the carousel takes its scrollable-page path (SingleChildScrollView) rather
// than the fixed-height path -- the fixed-height path has a pre-existing,
// unrelated ~6px height-estimate-vs-render drift that overflows regardless
// of which text widget is used (verified against the original SelectableText
// before this change), so real text content is kept short and visible at the
// top of the scroll view instead of relying on that path.
const _filler = 'Lorem ipsum dolor sit amet consectetur adipiscing elit. ';
final _longFiller = _filler * 40;

Widget _harness(List<BeaconFactCard> facts) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: BeaconPinnedFactCarousel(
        facts: facts,
        factTextStyle: const TextStyle(fontSize: 15),
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

  testWidgets('fact text renders without selection and link opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness([
        _fact('Check https://example.com for details. $_longFiller'),
      ]),
    );
    await tester.pumpAndSettle();

    // Dropped SelectableText in favor of a linkified, non-selectable Text.rich.
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

  testWidgets('plain fact text (no URL) still renders', (tester) async {
    await tester.pumpWidget(
      _harness([_fact('No links in this one. $_longFiller')]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No links in this one'), findsOneWidget);
  });
}
