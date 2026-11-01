// #930: on an iPhone SE in Russian the Request tab bar read «Обсужде… ❶»:
// a tab with an unread count kept an equal slot and its label was cut. The
// row now shares its width by content, so the label shows whole beside its
// count. Measured with the app font (Inter), as the #609 360 dp test does.

import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
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

  const sizes = {
    '375x667 with Plan': (Size(375, 667), true),
    '320x568': (Size(320, 568), false),
    'desktop 1280x800': (Size(1280, 800), true),
  };

  for (final locale in const [Locale('ru'), Locale('en')]) {
    for (final MapEntry(key: sizeName, value: (size, withPlan))
        in sizes.entries) {
      for (final (unread, shown) in const [(1, '1'), (9, '9'), (120, '99+')]) {
        testWidgets('${locale.languageCode} $sizeName, Discussion badge '
            '$shown: every tab label shows in full', (tester) async {
          await pumpBeaconViewHarness(
            tester,
            plan: withPlan ? kBeaconViewHarnessOneStepPlan : null,
            size: size,
            beaconState: beaconViewHarnessAuthorState(),
            threadsState: beaconViewHarnessThreadsState().copyWith(
              resolvedUnreadByThreadId: {RequestThread.generalId: unread},
            ),
            locale: locale,
          );
          await tester.pumpAndSettle();

          final l10n = lookupL10n(locale);
          final tabs = find.byType(BeaconSurfaceTabs);
          expect(tabs, findsOneWidget);
          // On a split desktop the discussion is a pane of its own, not a
          // tab; there the other labels are the guard.
          final chatIsTab = find
              .descendant(
                of: tabs,
                matching: find.text(l10n.labelBeaconTabChat),
              )
              .evaluate()
              .isNotEmpty;
          if (size.width < 600) expect(chatIsTab, isTrue);
          if (chatIsTab) {
            expect(
              find.descendant(of: tabs, matching: find.text(shown)),
              findsOneWidget,
              reason: 'the Discussion count is missing',
            );
          }
          for (final label in [
            l10n.labelBeaconTabNow,
            if (withPlan) l10n.labelBeaconTabPlan,
            if (chatIsTab) l10n.labelBeaconTabChat,
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
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
