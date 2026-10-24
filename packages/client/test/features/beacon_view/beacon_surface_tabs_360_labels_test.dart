// #609: on a 360 dp phone the Request tab bar keeps all four words, in
// English and in Russian, measured with the app font (Inter) rather than the
// test font, whose 1 em glyphs are far wider than any real label.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'beacon_view_screen_harness.dart';

Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('fonts/Inter-$weight.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

void main() {
  setUpAll(_loadInter);

  tearDown(unregisterBeaconViewHarnessGetIt);

  for (final locale in const [Locale('en'), Locale('ru')]) {
    testWidgets('360 dp, ${locale.languageCode}: all four tab labels show', (
      tester,
    ) async {
      await pumpBeaconViewHarness(
        tester,
        size: const Size(360, 800),
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
        locale: locale,
      );
      await tester.pumpAndSettle();

      final l10n = lookupL10n(locale);
      final tabs = find.byType(BeaconSurfaceTabs);
      expect(tabs, findsOneWidget);
      for (final label in [
        l10n.labelBeaconTabNow,
        l10n.labelBeaconTabPlan,
        l10n.labelBeaconTabChat,
        l10n.labelBeaconTabPeople,
      ]) {
        final text = find.descendant(of: tabs, matching: find.text(label));
        expect(text, findsOneWidget, reason: '$label is hidden');
        expect(
          tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
          reason: '$label is cut',
        );
      }
    });
  }
}
