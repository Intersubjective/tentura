// The narrow phone QA tests on (iPhone SE, 375×667). Fix completeness step 4
// (`.cursor/rules/fix-completeness.mdc`): every UI change is checked here, in RU.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPhone SE in logical pixels: the width QA reports phone bugs at.
const kPhoneSurface = Size(375, 667);

/// Sizes the test surface to [kPhoneSurface] and restores it when the test
/// ends.
Future<void> usePhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kPhoneSurface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// iPhone SE logical size at @2x device pixel ratio (physical 750×1334).
Future<void> usePhoneSurface2x(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(kPhoneSurface);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(() {
    tester.view.devicePixelRatio = 1.0;
    tester.binding.setSurfaceSize(null);
  });
}
