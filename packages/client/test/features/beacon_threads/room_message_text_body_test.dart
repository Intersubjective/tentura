import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Glyph ink extent (not the paragraph box, which includes leading) of the
/// first [length] characters, in global coordinates.
({double top, double bottom}) _globalInkRange(
  WidgetTester tester,
  Finder finder,
  int length,
) {
  final element = tester.element(finder.first);
  final box = element.renderObject! as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  final paragraph = box as RenderParagraph;
  final ink = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  return (top: origin.dy + ink.first.top, bottom: origin.dy + ink.first.bottom);
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

    final bodyRichText = find.descendant(
      of: find.byType(Stack),
      matching: find.byType(RichText),
    );
    final dateRichText = find.descendant(
      of: find.byType(PositionedDirectional),
      matching: find.byType(RichText),
    );
    final bodyInkBottom = _globalInkRange(tester, bodyRichText, display.length).bottom;
    final dateInkTop = _globalInkRange(tester, dateRichText, dateLine.length).top;

    expect(dateRect.bottom, closeTo(hostRect.bottom, 1));
    // Real gap, not a fraction-of-a-pixel offset that still reads as glued.
    expect(dateInkTop - bodyInkBottom, greaterThan(4));
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

  testWidgets(
    'bubble widened by a sibling (reply quote, footer, name) still anchors '
    'the date to the bubble edge, not the short text',
    (tester) async {
      const display = 'Hi';
      const dateLine = '12:34';
      const bubbleWidth = 260.0;

      // Mirrors room_message_tile's coreColumn: a Column with
      // crossAxisAlignment.start (loose width per child) at a fixed outer
      // width, with a sibling row wider than the message text alone.
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: _textDirection,
            child: MediaQuery(
              data: const MediaQueryData(textScaler: _textScaler),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const Key('bubble'),
                  width: bubbleWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: double.infinity,
                        child: Text('A much wider sibling row above the text'),
                      ),
                      RoomMessageTextBody(
                        display: display,
                        dateLine: dateLine,
                        bodyStyle: _bodyStyle,
                        metaStyle: _metaStyle,
                        metrics: _metricsFor(dateLine),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubbleRight = tester.getTopRight(find.byKey(const Key('bubble'))).dx;
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

      expect(dateRect.right, closeTo(bubbleRight, 1));
    },
  );
}
