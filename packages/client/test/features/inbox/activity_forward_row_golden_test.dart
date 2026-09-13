import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/activity_forward_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

AttentionReceipt _forwardReceipt({
  required AttentionForwardOutcome outcome,
  required String senderName,
}) {
  return AttentionReceipt(
    id: 'inbox:beacon-fwd-1',
    category: 'coordination',
    kind: 'newRelay',
    priority: 'normal',
    title: 'Garden cleanup',
    body: senderName,
    actionUrl: '/#/view?id=beacon-fwd-1',
    createdAt: DateTime.utc(2026, 6, 19, 16, 40),
    collapsedCount: 1,
    presentationKey: 'relay_received',
    presentationPayloadJson: '{}',
    surface: AttentionSurface.activity,
    beaconId: 'beacon-fwd-1',
    itemKind: AttentionItemKind.forward,
    forwardOutcome: outcome,
    forwardCount: 2,
  );
}

Future<void> _pumpRowGolden(
  WidgetTester tester, {
  required Size size,
  required Locale locale,
  required Brightness brightness,
  required AttentionForwardOutcome outcome,
  TextScaler? textScaler,
  required String goldenName,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final sender = locale.languageCode == 'ru' ? 'Глеб' : 'Gleb';

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: brightness == Brightness.light
          ? TenturaTheme.light()
          : TenturaTheme.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: textScaler ?? TextScaler.noScaling,
        ),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: const Key('golden'),
                child: SizedBox(
                  width: size.width,
                  child: ActivityForwardRow(
                    receipt: _forwardReceipt(
                      outcome: outcome,
                      senderName: sender,
                    ),
                    onOpenBeacon: () {},
                    onRestore: outcome == AttentionForwardOutcome.notInterested
                        ? () {}
                        : null,
                    onHide:
                        outcome == AttentionForwardOutcome.closedBeforeResponse ||
                            outcome ==
                                AttentionForwardOutcome.deletedBeforeResponse
                        ? () {}
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await expectLater(
    find.byKey(const Key('golden')),
    matchesGoldenFile('goldens/$goldenName'),
  );
}

void main() {
  const size = Size(360, 120);
  const outcomes = <AttentionForwardOutcome, String>{
    AttentionForwardOutcome.helping: 'helping',
    AttentionForwardOutcome.watching: 'watching',
    AttentionForwardOutcome.notInterested: 'not_interested',
    AttentionForwardOutcome.closedBeforeResponse: 'closed',
    AttentionForwardOutcome.deletedBeforeResponse: 'deleted',
  };

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light ? 'light' : 'dark';
    for (final locale in const [Locale('en'), Locale('ru')]) {
      final lang = locale.languageCode;
      for (final entry in outcomes.entries) {
        testWidgets(
          'forward row ${entry.value} $theme $lang',
          (tester) async {
            await _pumpRowGolden(
              tester,
              size: size,
              locale: locale,
              brightness: brightness,
              outcome: entry.key,
              goldenName:
                  'activity_forward_row_${entry.value}_${theme}_$lang.png',
            );
          },
        );
      }
    }
  }

  testWidgets('forward row helping 1.3x text scale', (tester) async {
    await _pumpRowGolden(
      tester,
      size: size,
      locale: const Locale('en'),
      brightness: Brightness.light,
      outcome: AttentionForwardOutcome.helping,
      textScaler: const TextScaler.linear(1.3),
      goldenName: 'activity_forward_row_helping_light_en_1p3x.png',
    );
  });
}
