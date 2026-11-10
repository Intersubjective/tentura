// The real app boot (main → App.runner) while another holder keeps the local
// database's cross-tab lock, as a frozen or background Tentura tab does. Boot
// must end on the lock-specific startup screen ("close other Tentura tabs"),
// not the generic startup failure after the 60 s boot timeout.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/app/boot_dependencies.dart';
import 'package:tentura/app/boot_failure_app.dart';
import 'package:tentura/design_system/components/tentura_empty_state.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/e2e_test_helpers.dart';

/// Holds the production database's lock from a separate request, forever.
Future<void> _holdDatabaseLockForever() async {
  final granted = Completer<void>();
  globalContext
      .getProperty<JSObject>('navigator'.toJS)
      .getProperty<JSObject>('locks'.toJS)
      .callMethod(
        'request'.toJS,
        'tentura:local-db:main_db'.toJS,
        ((JSAny? _) {
          granted.complete();
          return Completer<void>().future.toJS;
        }).toJS,
      );
  await granted.future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'web: boot with the local database held by another tab shows the '
    'close-other-tabs screen before the boot timeout',
    (tester) async {
      expect(kIsWeb, isTrue, reason: 'Run with flutter drive on Chrome');
      await _holdDatabaseLockForever();
      final watch = Stopwatch()..start();

      // App.runner returns once boot has failed and the startup screen runs.
      await launchApp(app.main).timeout(
        kBootTimeout + const Duration(seconds: 10),
      );
      await pumpUntilVisible(
        tester,
        find.byKey(TenturaEmptyState.bodyKey),
        timeout: const Duration(seconds: 10),
        label: 'startup error screen',
      );
      watch.stop();

      final l10n = lookupL10n(const Locale('en'));
      final body = tester
          .widget<Text>(find.byKey(TenturaEmptyState.bodyKey))
          .data;
      expect(body?.toLowerCase(), contains('close other tentura tabs'));
      expect(find.text(l10n.bootFailureTitle), findsNothing);
      expect(find.text(l10n.bootFailureBodyWeb), findsNothing);
      expect(find.byKey(BootFailureApp.reloadKey), findsOneWidget);
      expect(
        watch.elapsed,
        lessThan(kBootTimeout),
        reason: 'boot must not wait for the generic 60 s boot timeout',
      );
    },
  );
}
