import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/features/evaluation/domain/entity/evaluation_value.dart';
import 'package:tentura/features/evaluation/ui/widget/evaluation_impact_control.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void _ignore(EvaluationValue _) {}

Widget _goldenApp({required ThemeData theme, required EvaluationValue? value}) {
  return MaterialApp(
    theme: theme,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(320, 700)),
      child: TenturaResponsiveScope(
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('evaluation-impact-golden-boundary'),
            child: SizedBox(
              width: 320,
              child: EvaluationImpactControl(value: value, onChanged: _ignore),
            ),
          ),
        ),
      ),
    ),
  );
}

void _setActualSurface(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(320, 700)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('impact control light 320px', (tester) async {
    _setActualSurface(tester);
    await tester.pumpWidget(
      _goldenApp(theme: TenturaTheme.light(), value: null),
    );
    await expectLater(
      find.byKey(const ValueKey('evaluation-impact-golden-boundary')),
      matchesGoldenFile('goldens/evaluation_impact_control_light_320.png'),
    );
  });

  testWidgets('impact control dark 320px selected state', (tester) async {
    _setActualSurface(tester);
    await tester.pumpWidget(
      _goldenApp(theme: TenturaTheme.dark(), value: EvaluationValue.pos1),
    );
    await expectLater(
      find.byKey(const ValueKey('evaluation-impact-golden-boundary')),
      matchesGoldenFile('goldens/evaluation_impact_control_dark_320.png'),
    );
  });
}
