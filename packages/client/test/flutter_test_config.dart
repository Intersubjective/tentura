import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Per-test timeout for `testWidgets` in this package.
///
/// `testWidgets` passes the binding's `defaultTestTimeout` (10 min) to
/// package:test explicitly, so `flutter test --timeout` and `dart_test.yaml`
/// never reach widget tests. A widget test that awaits a future which cannot
/// complete under fake async then hangs for 10 minutes per test, or until the
/// wrapper's whole-run timeout kills the suite with no hint of which test hung.
/// Two minutes is far above any widget test here (the slowest whole file runs
/// in under two minutes); a test that needs longer passes its own `timeout:`.
const kWidgetTestTimeout = Timeout(Duration(minutes: 2));

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (binding is AutomatedTestWidgetsFlutterBinding) {
    binding.defaultTestTimeout = kWidgetTestTimeout;
  }
  await testMain();
}
