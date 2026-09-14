import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/constellation_reference_fixture.dart';

final class _NonLinearTextScaler extends TextScaler {
  @override
  double get textScaleFactor => 1.0;

  @override
  double scale(double fontSize) => math.min(fontSize * 2, fontSize + 6);

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = 4}) =>
      this;
}

void main() {
  testWidgets('body syncs dimensionless text scale ratio from TextScaler', (
    tester,
  ) async {
    final cubit = await loadReferenceCubit();
    addTearDown(cubit.close);

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: TextScaler.linear(1.0),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, 1.0);

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: TextScaler.linear(1.3),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, closeTo(1.3, 1e-9));

    await pumpConstellationBody(
      tester,
      cubit,
      textScaler: _NonLinearTextScaler(),
    );
    await tester.pump();
    expect(cubit.labelBudgetTextScaleForTest, closeTo(19 / 13, 1e-9));
  });
}
