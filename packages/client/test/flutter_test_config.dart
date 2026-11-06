import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/ui/util/constellation_forward_tree_request.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_field_topo_backdrop.dart';

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
  // The Field's topographic backdrop (#1022) stays out of widget tests so
  // golden and layout tests are undisturbed; its own test turns it on.
  ConstellationFieldTopoBackdrop.enabled = false;
  // The forward-tree entry request is a process-wide one-shot (#774 31ve.6):
  // a test that schedules it and never mounts the Field would leave it pending
  // for the next Field test in the same bundle isolate, which then draws the
  // overlay and rebuilds every node tile.
  tearDown(() => ConstellationForwardTreeRequest.instance.take());
  await testMain();
}
