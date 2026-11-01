// Review of PR #935 (finding 5): TenturaUnderlineTabs sizes its tabs with
// TenturaCountBadge.widthFor instead of a copy of the badge's padding,
// minimum and 99+ cap, so the measure is the badge's own: it equals the width
// the badge renders at.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/components/tentura_count_badge.dart';

void main() {
  for (final (count, label) in const [
    (1, '1'),
    (9, '9'),
    (42, '42'),
    (99, '99'),
    (120, '99+'),
  ]) {
    testWidgets('count $count: widthFor matches the rendered badge', (
      tester,
    ) async {
      late double measured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) {
                  measured = TenturaCountBadge.widthFor(context, count);
                  // In a Row, as in the tab bar: the badge sizes to its count.
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TenturaCountBadge(
                        count: count,
                        backgroundColor: Colors.blue,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      expect(find.text(label), findsOneWidget);
      expect(TenturaCountBadge.label(count), label);
      final rendered = tester.getSize(find.byType(TenturaCountBadge)).width;
      expect(measured, moreOrLessEquals(rendered, epsilon: 0.01));
      expect(measured, greaterThanOrEqualTo(TenturaCountBadge.minSize));
    });
  }
}
