import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  Future<void> pumpChips(
    WidgetTester tester, {
    required Size logicalSize,
    required Brightness brightness,
    required Locale locale,
    double textScaler = 1,
  }) async {
    final l10n = lookupL10n(locale);
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TenturaRelationChip(
                          label: l10n.attentionRelationHelping,
                          tone: TenturaRelationTone.helping,
                        ),
                        const SizedBox(width: TenturaSpacing.row),
                        TenturaRelationChip(
                          label: l10n.inboxWatching,
                          tone: TenturaRelationTone.following,
                        ),
                      ],
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
          'relation chips ${brightness.name} ${locale.languageCode} $width',
          (tester) async {
            final size = Size(width, 60);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));

            await pumpChips(
              tester,
              logicalSize: size,
              brightness: brightness,
              locale: locale,
            );

            await expectLater(
              find.byKey(const Key('golden')),
              matchesGoldenFile(
                'goldens/tentura_relation_chip_'
                '${brightness.name}_${locale.languageCode}_$width.png',
              ),
            );
          },
          tags: 'golden',
        );
      }
    }
  }

  testWidgets('relation chips text scale 1.3', (tester) async {
    const size = Size(360, 80);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpChips(
      tester,
      logicalSize: size,
      brightness: Brightness.light,
      locale: const Locale('ru'),
      textScaler: 1.3,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/tentura_relation_chip_light_ru_360_s1_3.png'),
    );
  },
    tags: 'golden',
  );
}
