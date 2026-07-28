import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_definition_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

class _FakePlatformRepository implements PlatformRepositoryPort {
  Uri? launchedUri;
  Uri? launchedUserLink;

  @override
  Future<String> getAppVersion() async => 'test';

  @override
  Future<String> getStringFromClipboard() async => '';

  @override
  Future<void> launchUri(Uri uri) async {
    launchedUri = uri;
  }

  @override
  Future<void> launchUrl(String uri) async {
    launchedUri = Uri.parse(uri);
  }

  @override
  Future<void> launchUserLink(Uri uri) async {
    launchedUserLink = uri;
  }
}

Widget _harness(Beacon beacon) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(
      body: BeaconDefinitionBody(beacon: beacon),
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

  testWidgets('description link opens via launchUserLink', (tester) async {
    final beacon = Beacon.empty.copyWith(
      id: 'b-desc-link',
      description: 'Check https://example.com for info',
    );

    await tester.pumpWidget(_harness(beacon));
    await tester.pumpAndSettle();

    final richTextFinder = find.descendant(
      of: find.byType(BeaconDefinitionBody),
      matching: find.byType(RichText),
    );
    final richText = tester.widget<RichText>(richTextFinder.first);
    final renderParagraph =
        tester.element(richTextFinder.first).renderObject! as RenderParagraph;
    final text = richText.text.toPlainText();
    final linkStart = text.indexOf('https://');
    final boxes = renderParagraph.getBoxesForSelection(
      TextSelection(baseOffset: linkStart, extentOffset: linkStart + 1),
    );
    final point = renderParagraph.localToGlobal(
      boxes.first.toRect().center,
    );

    await tester.tapAt(point);
    await tester.pumpAndSettle();

    expect(platform.launchedUserLink, Uri.parse('https://example.com'));
  });
}
