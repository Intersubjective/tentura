import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _anna = Profile(id: 'u1', displayName: 'Anna');

final _receipt = AttentionReceipt(
  id: 'e1',
  category: 'requestProgress',
  kind: 'relayReceived',
  priority: 'normal',
  title: 'Anna',
  body: 'Forwarded you a request',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 6, 19, 16, 40),
  collapsedCount: 1,
  presentationKey: 'relay_received',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.activity,
  actorUserId: 'u1',
);

String _note(Locale locale) => switch (locale.languageCode) {
  'ru' => 'Ты же с этим возился, глянь',
  _ => 'You dealt with this once — take a look',
};

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required Size logicalSize,
    required Brightness brightness,
    required Locale locale,
    double textScaler = 1,
  }) async {
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
            size: logicalSize,
            textScaler: TextScaler.linear(textScaler),
          ),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: RepaintBoundary(
                  key: const Key('golden'),
                  child: SizedBox(
                    width: logicalSize.width,
                    child: AttentionMiniCard(
                      receipt: _receipt,
                      kind: AttentionMiniCardKind.forward,
                      actor: _anna,
                      quotedBody: _note(locale),
                      capabilitySlugs: const ['transport', 'tools'],
                      onDismiss: () {},
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
  }

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final width in const <double>[360, 390]) {
        testWidgets(
          'mini-card forward ${brightness.name} ${locale.languageCode} $width',
          (tester) async {
            final size = Size(width, 160);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));

            await pumpCard(
              tester,
              logicalSize: size,
              brightness: brightness,
              locale: locale,
            );

            await expectLater(
              find.byKey(const Key('golden')),
              matchesGoldenFile(
                'goldens/attention_mini_card_forward_'
                '${brightness.name}_${locale.languageCode}_$width.png',
              ),
            );
          },
        );
      }
    }
  }

  testWidgets('mini-card forward text scale 1.3', (tester) async {
    const size = Size(360, 260);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpCard(
      tester,
      logicalSize: size,
      brightness: Brightness.light,
      locale: const Locale('ru'),
      textScaler: 1.3,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile(
        'goldens/attention_mini_card_forward_light_ru_360_s1_3.png',
      ),
    );
  });
}
