// #905: the author's close preview heading reads as a full phrase
// («What each helper gets by default»), with one secondary line under it
// («if the others don't respond»), in EN and RU; on a 375×667 phone in RU
// nothing is clipped.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_member.dart';
import 'package:tentura/features/closure/domain/entity/closure_role.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/ui/bloc/closure_helper_cubit.dart';
import 'package:tentura/features/closure/ui/widget/closure_preview.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _phone = Size(375, 667);

const _copy = {
  'en': (
    title: 'What each helper gets by default',
    line: "if the others don't respond",
  ),
  'ru': (
    title: 'Что получит каждый помощник по умолчанию',
    line: 'если остальные не ответят',
  ),
};

final _state = ClosureState(
  epoch: 2,
  status: kClosureStatusEvaluating,
  role: ClosureRole.author,
  members: const [
    ClosureMember(id: 'u1', displayName: 'Name u1'),
    ClosureMember(id: 'u2', displayName: 'Name u2'),
  ],
  closesAt: DateTime.utc(2030, 1, 10, 12),
  outcomes: const {},
);

Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.view
    ..physicalSize = _phone
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(TenturaSpacing.screenH),
          child: ClosurePreview(data: _state, beaconId: 'Bclosure00905'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in _copy.entries) {
    testWidgets('${entry.key}: heading and the line under it, 375×667, '
        'nothing clipped', (tester) async {
      await _pump(tester, Locale(entry.key));
      expect(tester.takeException(), isNull);
      final title = find.text(entry.value.title);
      final line = find.text(entry.value.line);
      expect(title, findsOneWidget);
      expect(line, findsOneWidget);
      // The line sits right under the heading.
      expect(
        tester.getTopLeft(line).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );
      final theme = Theme.of(tester.element(title));
      final lineText = tester.widget<Text>(line);
      expect(lineText.style?.fontSize, theme.textTheme.bodySmall?.fontSize);
      for (final f in [title, line]) {
        final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: f, matching: find.byType(RichText)),
        );
        expect(p.didExceedMaxLines, isFalse);
        expect(tester.getBottomRight(f).dx, lessThanOrEqualTo(_phone.width));
      }
    });
  }
}
