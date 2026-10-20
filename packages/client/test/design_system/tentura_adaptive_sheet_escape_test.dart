// #403: Escape closes app sheets/dialogs opened through
// showTenturaAdaptiveSheet, and keyboard focus returns to the control that
// opened them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

const _compact = Size(390, 844);
const _wide = Size(1280, 1100);

Widget _harness({
  required FocusNode triggerFocus,
  bool stacked = false,
}) => MaterialApp(
  theme: TenturaTheme.light(),
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          focusNode: triggerFocus,
          onPressed: () => showTenturaAdaptiveSheet<void>(
            context: context,
            builder: (sheetContext) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('First sheet'),
                  if (stacked)
                    TextButton(
                      onPressed: () => showTenturaAdaptiveSheet<void>(
                        context: sheetContext,
                        builder: (_) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Second sheet'),
                        ),
                      ),
                      child: const Text('Open second'),
                    ),
                ],
              ),
            ),
          ),
          child: const Text('Open sheet'),
        ),
      ),
    ),
  ),
);

Future<void> _pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [('compact', _compact), ('wide', _wide)]) {
    group('showTenturaAdaptiveSheet ($name)', () {
      late FocusNode triggerFocus;

      setUp(() => triggerFocus = FocusNode(debugLabel: 'trigger'));
      tearDown(() => triggerFocus.dispose());

      Future<void> pump(WidgetTester tester, {bool stacked = false}) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _harness(triggerFocus: triggerFocus, stacked: stacked),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('Escape closes the sheet and focus returns to the trigger', (
        tester,
      ) async {
        await pump(tester);

        triggerFocus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('First sheet'), findsOneWidget);
        expect(triggerFocus.hasPrimaryFocus, isFalse);

        await _pressEscape(tester);

        expect(find.text('First sheet'), findsNothing);
        expect(find.text('Open sheet'), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, same(triggerFocus));
      });

      testWidgets('Escape closes the sheet when focus is parked outside it', (
        tester,
      ) async {
        await pump(tester);

        await tester.tap(find.text('Open sheet'));
        await tester.pumpAndSettle();
        expect(find.text('First sheet'), findsOneWidget);

        // What the web View does when the browser moves DOM focus away.
        FocusManager.instance.rootScope.requestScopeFocus();
        await tester.pump();

        await _pressEscape(tester);

        expect(find.text('First sheet'), findsNothing);
        expect(find.text('Open sheet'), findsOneWidget);
      });

      testWidgets(
        'Escape with focus left on the trigger closes the sheet only',
        (
          tester,
        ) async {
          await pump(tester);

          await tester.tap(find.text('Open sheet'));
          await tester.pumpAndSettle();
          expect(find.text('First sheet'), findsOneWidget);

          // Focus lands on the trigger under the open sheet (a late browser
          // focus event after the click).
          triggerFocus.requestFocus();
          await tester.pump();

          await _pressEscape(tester);

          expect(find.text('First sheet'), findsNothing);
          expect(find.text('Open sheet'), findsOneWidget);
        },
      );

      testWidgets('Escape on a stacked sheet closes only the top one', (
        tester,
      ) async {
        await pump(tester, stacked: true);

        await tester.tap(find.text('Open sheet'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open second'));
        await tester.pumpAndSettle();
        expect(find.text('Second sheet'), findsOneWidget);

        await _pressEscape(tester);

        expect(find.text('Second sheet'), findsNothing);
        expect(find.text('First sheet'), findsOneWidget);

        await _pressEscape(tester);

        expect(find.text('First sheet'), findsNothing);
        expect(find.text('Open sheet'), findsOneWidget);
      });
    });
  }
}
