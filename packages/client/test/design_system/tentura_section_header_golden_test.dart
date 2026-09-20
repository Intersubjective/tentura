import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const widths = <double>[360, 390];

  String _sectionLabel(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Для вас',
        _ => 'For you',
      };

  Future<void> pumpHeader(
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
                    child: TenturaSectionHeader(
                      label: _sectionLabel(locale),
                      count: 4,
                      helperText: l10n.myWorkFinishedHint,
                      semanticsIdentifier: 'golden-section-header',
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
      for (final width in widths) {
        testWidgets(
          'section header ${brightness.name} ${locale.languageCode} $width',
          (tester) async {
            final size = Size(width, 160);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));

            await pumpHeader(
              tester,
              logicalSize: size,
              brightness: brightness,
              locale: locale,
            );

            await expectLater(
              find.byKey(const Key('golden')),
              matchesGoldenFile(
                'goldens/tentura_section_header_'
                '${brightness.name}_${locale.languageCode}_$width.png',
              ),
            );
          },
          tags: 'golden',
        );
      }
    }
  }

  testWidgets('section header text scale 1.3', (tester) async {
    const size = Size(360, 180);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHeader(
      tester,
      logicalSize: size,
      brightness: Brightness.light,
      locale: const Locale('en'),
      textScaler: 1.3,
    );

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile('goldens/tentura_section_header_light_en_360_s1_3.png'),
    );
  },
    tags: 'golden',
  );
}
