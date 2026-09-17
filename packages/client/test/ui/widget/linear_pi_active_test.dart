import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/widget/linear_pi_active.dart';

void main() {
  testWidgets('LinearPiActive does not animate when disableAnimations is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: LinearPiActive()),
        ),
      ),
    );
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.5);

    // A repeating controller would keep scheduling frames; with reduced
    // motion, settle must complete immediately.
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
  });

  testWidgets('LinearPiActive animates when motion is allowed', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(),
        child: MaterialApp(
          home: Scaffold(body: LinearPiActive()),
        ),
      ),
    );
    await tester.pump();
    final first = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    await tester.pump(const Duration(milliseconds: 100));
    final second = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value!;
    expect(second, isNot(first));
  });
}
