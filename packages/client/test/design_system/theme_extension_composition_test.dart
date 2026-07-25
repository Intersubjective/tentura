import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

void main() {
  group('TenturaCapabilityColors theme composition', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final width in [400.0, 700.0, 1000.0]) {
        final wc = windowClassForWidth(width);
        testWidgets(
          '$brightness × $wc exposes exact capability swatches',
          (tester) async {
            final theme = brightness == Brightness.light
                ? TenturaTheme.light()
                : TenturaTheme.dark();
            final expected = brightness == Brightness.light
                ? TenturaCapabilityColors.light
                : TenturaCapabilityColors.dark;

            late TenturaCapabilityColors colors;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(size: Size(width, 800)),
                  child: TenturaResponsiveScope(
                    child: Builder(
                      builder: (context) {
                        colors = context.capabilityColors;
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
              ),
            );

            expect(colors.logistics, expected.logistics);
            expect(colors.communication, expected.communication);
            expect(colors.knowledge, expected.knowledge);
            expect(colors.care, expected.care);
            expect(colors.resources, expected.resources);
            expect(colors.technical, expected.technical);
            expect(colors.special, expected.special);
            expect(
              Theme.of(
                tester.element(find.byType(SizedBox)),
              ).extension<TenturaTokens>(),
              isNotNull,
            );
          },
        );
      }
    }

    testWidgets('capabilityColors fails fast when extension is absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              expect(
                () => context.capabilityColors,
                throwsA(isA<TypeError>()),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
