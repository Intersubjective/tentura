import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';

const _textDirection = TextDirection.ltr;
const _textScaler = TextScaler.noScaling;

const _bodyStyle = TextStyle(fontSize: 15, height: 1.4);
const _metaStyle = TextStyle(fontSize: 12, height: 1.2);

TrailingMetaMetrics _metricsFor(String dateLine) => computeTrailingMetaMetrics(
  dateLine: dateLine,
  metaStyle: _metaStyle,
  trailingGap: 4,
  textDirection: _textDirection,
  textScaler: _textScaler,
);

Rect _globalRect(WidgetTester tester, Finder finder) {
  final element = tester.element(finder.first);
  final box = element.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

Widget _harness({
  required Widget child,
  required double width,
}) {
  return MaterialApp(
    home: Directionality(
      textDirection: _textDirection,
      child: MediaQuery(
        data: const MediaQueryData(
          textScaler: _textScaler,
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: child,
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('short text: date tucked to body bottom, not shared baseline top',
      (tester) async {
    const display = 'Hi';
    const dateLine = '12:34';

    await tester.pumpWidget(
      _harness(
        width: 240,
        child: RoomMessageTextBody(
          display: display,
          dateLine: dateLine,
          bodyStyle: _bodyStyle,
          metaStyle: _metaStyle,
          metrics: _metricsFor(dateLine),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hostRect = _globalRect(tester, find.byType(RoomMessageTextBody));
    final bodyRect = _globalRect(
      tester,
      find.descendant(
        of: find.byType(Stack),
        matching: find.byType(RichText),
      ),
    );
    final dateRect = _globalRect(
      tester,
      find.descendant(
        of: find.byType(RoomMessageTextBody),
        matching: find.descendant(
          of: find.byType(PositionedDirectional),
          matching: find.text(dateLine),
        ),
      ),
    );

    expect(dateRect.bottom, closeTo(hostRect.bottom, 1));
    expect(dateRect.top, greaterThan(bodyRect.top));
  });

  testWidgets('wrapped skip keeps date on the right, not at line start',
      (tester) async {
    const display =
        'Almost full line of text that leaves no room for trailing meta';
    const dateLine = '23:59';

    await tester.pumpWidget(
      _harness(
        width: 180,
        child: RoomMessageTextBody(
          display: display,
          dateLine: dateLine,
          bodyStyle: _bodyStyle,
          metaStyle: _metaStyle,
          metrics: _metricsFor(dateLine),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final hostRect = _globalRect(tester, find.byType(RoomMessageTextBody));
    final dateRect = _globalRect(
      tester,
      find.descendant(
        of: find.byType(RoomMessageTextBody),
        matching: find.descendant(
          of: find.byType(PositionedDirectional),
          matching: find.text(dateLine),
        ),
      ),
    );

    expect(dateRect.center.dx, greaterThan(hostRect.center.dx));
    expect(dateRect.left, greaterThan(hostRect.left + hostRect.width * 0.45));
  });
}
