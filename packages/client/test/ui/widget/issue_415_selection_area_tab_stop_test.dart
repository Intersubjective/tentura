// #415: on desktop/web every block of selectable text (message bodies,
// pinned facts, the request description, reply quotes) is wrapped in
// TenturaSelectionArea, and Flutter's SelectionArea owns a focus node that
// Tab stops on. Each such block became an extra, invisible Tab stop right
// after the control that holds it ("message x2", "pinned fact x2" ...).
//
// Spec: the selectable text is not a Tab stop of its own (Tab goes from the
// control before it straight to the control after it), while mouse text
// selection stays on desktop (the SelectionArea is still there) and still
// works from the keyboard once clicked: a click puts focus in the text and
// Ctrl+A, Ctrl+C (Cmd on macOS) copy it. A fix that makes the area
// unfocusable (ExcludeFocus, canRequestFocus: false ...) breaks that copy.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

const _before = 'Control before';
const _after = 'Control after';
const _body = 'Selectable message body';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      // Built inside the test body, so it picks up the desktop platform.
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(onPressed: () {}, child: const Text(_before)),
            const TenturaSelectionArea(child: Text(_body)),
            ElevatedButton(onPressed: () {}, child: const Text(_after)),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The focus node of the button whose label is [label].
FocusNode _buttonNode(WidgetTester tester, String label) =>
    Focus.of(tester.element(find.text(label)));

String _describeFocus() {
  final focus = FocusManager.instance.primaryFocus;
  return '${focus?.debugLabel ?? focus?.runtimeType} '
      '(${focus?.context?.widget.runtimeType})';
}

void main() {
  testWidgets(
    '#415 desktop: Tab skips over selectable text to the next control',
    (tester) async {
      await _pump(tester);
      expect(
        tenturaDesktopSelectionEnabledFor(
          Theme.of(tester.element(find.text(_body))),
        ),
        isTrue,
        reason: 'precondition: desktop platform under test',
      );
      // Mouse selection stays: the text is still inside a SelectionArea.
      expect(
        find.ancestor(
          of: find.text(_body),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
        reason: 'desktop keeps text selection (no fix by dropping it)',
      );

      _buttonNode(tester, _before).requestFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(_buttonNode(tester, _before)),
        reason: 'precondition: the first control has focus',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(
        FocusManager.instance.primaryFocus,
        same(_buttonNode(tester, _after)),
        reason:
            'one Tab goes past the selectable text to the next control; '
            'focus is on ${_describeFocus()}',
      );

      // And back: Shift+Tab returns to the first control in one press.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        same(_buttonNode(tester, _before)),
        reason:
            'Shift+Tab also skips the selectable text; '
            'focus is on ${_describeFocus()}',
      );
    },
    variant: TargetPlatformVariant.desktop(),
  );
  testWidgets(
    '#415 desktop: clicked text keeps focus and copies with Ctrl+A, Ctrl+C',
    (tester) async {
      await _pump(tester);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              ((call.arguments as Map<Object?, Object?>)['text'] ?? '')
                  as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.tap(find.text(_body), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));
      await expectFocusInSelectionArea(tester, find.text(_body));

      await sendSelectAllAndCopy(tester);
      expect(
        copied.join(),
        contains(_body),
        reason: 'Ctrl+A, Ctrl+C after a click copies the text',
      );
    },
    variant: TargetPlatformVariant.desktop(),
  );
}

/// Expects the primary focus to sit in the [SelectionArea] around [text].
Future<void> expectFocusInSelectionArea(
  WidgetTester tester,
  Finder text,
) async {
  final area = tester.element(
    find.ancestor(of: text, matching: find.byType(SelectionArea)).first,
  );
  final focused = FocusManager.instance.primaryFocus?.context;
  var inside = false;
  if (focused != null) {
    if (identical(focused, area)) inside = true;
    focused.visitAncestorElements((e) {
      if (identical(e, area)) inside = true;
      return !inside;
    });
  }
  expect(
    inside,
    isTrue,
    reason:
        'a click into the text focuses its SelectionArea '
        '(text stays keyboard-copyable); focus is on ${_describeFocus()}',
  );
}

/// Sends Select all, then Copy, with the platform's shortcut modifier.
Future<void> sendSelectAllAndCopy(WidgetTester tester) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}
