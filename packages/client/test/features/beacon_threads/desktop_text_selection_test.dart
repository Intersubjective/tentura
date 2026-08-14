import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_reply_quote.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_definition_body.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

ThemeData _desktopTheme() => TenturaTheme.light().copyWith(
  platform: TargetPlatform.macOS,
);

Widget _desktopHarness(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    theme: _desktopTheme(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: TenturaResponsiveScope(
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoomMessageTextBody desktop selection', () {
    const bodyStyle = TextStyle(fontSize: 15, height: 1.4);
    const metaStyle = TextStyle(fontSize: 12, height: 1.2);

    testWidgets('wraps body in SelectionArea on macOS', (tester) async {
      final metrics = computeTrailingMetaMetrics(
        dateLine: '14:02',
        bodyStyle: bodyStyle,
        metaStyle: metaStyle,
        trailingGap: 4,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );

      await tester.pumpWidget(
        _desktopHarness(
          SizedBox(
            width: 280,
            child: RoomMessageTextBody(
              display: 'IBAN DE89 3704 0044 0532 0130 00',
              dateLine: '14:02',
              bodyStyle: bodyStyle,
              metaStyle: metaStyle,
              metrics: metrics,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectionContainer), findsWidgets);
    });

    testWidgets('mouse drag selects body fragment without timestamp', (
      tester,
    ) async {
      const display = 'Meet at Hauptstraße 12 Berlin';
      final metrics = computeTrailingMetaMetrics(
        dateLine: '14:02 · Edited',
        bodyStyle: bodyStyle,
        metaStyle: metaStyle,
        trailingGap: 4,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      );

      await tester.pumpWidget(
        _desktopHarness(
          SizedBox(
            width: 320,
            child: RoomMessageTextBody(
              display: display,
              dateLine: '14:02 · Edited',
              bodyStyle: bodyStyle,
              metaStyle: metaStyle,
              metrics: metrics,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains('Meet at Hauptstraße'),
      );
      final richText = tester.renderObject<RenderParagraph>(richTextFinder);
      final boxes = richText.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
      );
      expect(boxes, isNotEmpty);

      final start = richText.localToGlobal(boxes.first.toRect().topLeft);
      final endBoxes = richText.getBoxesForSelection(
        const TextSelection(baseOffset: 8, extentOffset: 12),
      );
      final end = richText.localToGlobal(endBoxes.first.toRect().centerRight);

      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });

  group('RoomMessageReplyQuote desktop selection', () {
    testWidgets('mouse drag on excerpt does not jump to parent', (tester) async {
      String? jumped;
      await tester.pumpWidget(
        _desktopHarness(
          SizedBox(
            width: 300,
            child: RoomMessageReplyQuote(
              authorName: 'Anna',
              excerpt: 'Bring the ladder tomorrow morning please',
              unavailable: false,
              replyToMessageId: 'parent-1',
              onJumpToReply: (id) => jumped = id,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText().contains('Bring the ladder'),
      );
      final richText = tester.renderObject<RenderParagraph>(richTextFinder);
      final start = richText.localToGlobal(Offset.zero);
      final end = richText.localToGlobal(
        Offset(richText.size.width * 0.6, richText.size.height / 2),
      );

      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveTo(end);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(jumped, isNull);
      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });

  group('BeaconDefinitionBody desktop selection', () {
    testWidgets('expanded description is wrapped in SelectionArea', (
      tester,
    ) async {
      await tester.pumpWidget(
        _desktopHarness(
          BeaconDefinitionBody(
            beacon: Beacon(
              id: 'b1',
              title: 'Help moving',
              description: 'Need two people at Hauptstraße 12 on Saturday.',
              author: const Profile(id: 'u1', displayName: 'Author'),
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(
        find.text('Need two people at Hauptstraße 12 on Saturday.'),
        findsOneWidget,
      );
    });
  });
}
