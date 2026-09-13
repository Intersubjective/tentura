import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  const widths = <double>[360, 390];

  String _matrixLabel(Locale locale) {
    final l10n = lookupL10n(locale);
    return l10n.activityTriageRequestsNeedResponse(2);
  }

  for (final brightness in Brightness.values) {
    for (final locale in const [Locale('en'), Locale('ru')]) {
      for (final width in widths) {
        testWidgets(
          'summary row ${brightness.name} ${locale.languageCode} $width',
          (tester) async {
            final size = Size(width, 120);
            await tester.binding.setSurfaceSize(size);
            addTearDown(() => tester.binding.setSurfaceSize(null));

            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                theme: brightness == Brightness.light
                    ? TenturaTheme.light()
                    : TenturaTheme.dark(),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: Builder(
                  builder: (context) {
                    final label = _matrixLabel(locale);
                    return MediaQuery(
                      data: MediaQueryData(size: size),
                      child: TenturaResponsiveScope(
                        child: Scaffold(
                          body: Align(
                            alignment: Alignment.topCenter,
                            child: RepaintBoundary(
                              key: const Key('golden'),
                              child: SizedBox(
                                width: width,
                                child: Padding(
                                  padding: EdgeInsets.all(context.tt.rowGap),
                                  child: TenturaAttentionSummaryRow(
                                    label: label,
                                    semanticsLabel: label,
                                    onTap: () {},
                                    leading: Icon(
                                      Icons.mail_outline,
                                      size: context.tt.iconSize,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();

            await expectLater(
              find.byKey(const Key('golden')),
              matchesGoldenFile(
                'goldens/tentura_attention_summary_row_'
                '${brightness.name}_${locale.languageCode}_$width.png',
              ),
            );
          },
        );
      }
    }
  }

  testWidgets('summary row collapsed style text scale 1.3', (tester) async {
    const size = Size(360, 120);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            final label =
                lookupL10n(const Locale('en')).activityPromptCollapsedBatch(3);
            return MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1.3),
              ),
              child: TenturaResponsiveScope(
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(
                      key: const Key('golden'),
                      child: SizedBox(
                        width: size.width,
                        child: TenturaAttentionSummaryRow(
                          label: label,
                          maxLines: 2,
                          showChevron: false,
                          semanticsLabel: label,
                          onTap: () {},
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('golden')),
      matchesGoldenFile(
        'goldens/tentura_attention_summary_row_collapsed_light_en_360_s1_3.png',
      ),
    );
  });
}
