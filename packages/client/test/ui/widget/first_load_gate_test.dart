import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

const _content = 'Primary screen content';

Future<void> _pumpGate(
  WidgetTester tester, {
  ValueNotifier<bool>? readiness,
  Object? error,
  VoidCallback? onRetry,
}) {
  final ready = readiness ?? ValueNotifier(false);
  if (readiness == null) addTearDown(ready.dispose);
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (context, isReady, child) => TenturaFirstLoadGate(
            ready: isReady,
            error: error,
            onRetry: onRetry ?? () {},
            child: const Text(_content),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Initial screen loading', () {
    testWidgets('delays the spinner and reveals content after the timeout', (
      tester,
    ) async {
      await _pumpGate(tester);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_content), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ScreenLoadErrorPanel), findsNothing);

      await tester.pump(const Duration(milliseconds: 49)); // 149 ms
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_content), findsNothing);

      await tester.pump(const Duration(milliseconds: 2)); // 151 ms
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_content), findsNothing);

      await tester.pump(const Duration(milliseconds: 49)); // 200 ms
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_content), findsNothing);

      await tester.pump(const Duration(milliseconds: 2299)); // 2499 ms
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_content), findsNothing);

      await tester.pump(const Duration(milliseconds: 2)); // 2501 ms
      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 99)); // 2600 ms
      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('reveals available content even when readiness never arrives', (
      tester,
    ) async {
      await _pumpGate(tester);
      await tester.pump(const Duration(milliseconds: 2499));
      expect(find.text(_content), findsNothing);
      await tester.pump(const Duration(milliseconds: 2));

      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ScreenLoadErrorPanel), findsNothing);
    });

    testWidgets('shows a load error panel with a working retry action', (
      tester,
    ) async {
      var retries = 0;
      await _pumpGate(
        tester,
        error: const ConnectionUplinkException(),
        onRetry: () => retries++,
      );
      await tester.pump();

      expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
      expect(find.text(_content), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final context = tester.element(find.byType(ScreenLoadErrorPanel));
      final l10n = L10n.of(context)!;
      expect(find.text(l10n.screenLoadErrorNetworkTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.myWorkRetry));
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('keeps content visible during refresh after becoming ready', (
      tester,
    ) async {
      final readiness = ValueNotifier(false);
      addTearDown(readiness.dispose);
      await _pumpGate(tester, readiness: readiness);
      await tester.pump(const Duration(milliseconds: 50));
      readiness.value = true;
      await tester.pump();
      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      readiness.value = false;
      await tester.pump();

      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 2600));
      expect(find.text(_content), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
