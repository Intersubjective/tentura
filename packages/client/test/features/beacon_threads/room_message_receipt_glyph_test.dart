// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewport = Size(320, 120);

Widget _harness(
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: MediaQuery(
      data: const MediaQueryData(size: _viewport),
      child: TenturaResponsiveScope(
        child: Scaffold(
          body: Center(child: child),
        ),
      ),
    ),
  );
}

Icon _singleGlyphIcon(WidgetTester tester) {
  expect(find.byType(Icon), findsOneWidget);
  return tester.widget<Icon>(find.byType(Icon));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoomMessageReceiptGlyph', () {
    testWidgets('pending shows schedule icon, muted color, and Sending semantics',
        (tester) async {
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;

      await tester.pumpWidget(
        _harness(
          RoomMessageReceiptGlyph(
            receipt: const RoomMessageReceipt(
              state: RoomMessageReceiptState.pending,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = _singleGlyphIcon(tester);
      expect(icon.icon, Icons.schedule);
      expect(icon.size, 12);
      expect(icon.color, tt.textMuted);
      expect(find.bySemanticsLabel('Sending…'), findsOneWidget);
    });

    testWidgets('sent shows done icon, muted color, and Sent semantics',
        (tester) async {
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;

      await tester.pumpWidget(
        _harness(
          RoomMessageReceiptGlyph(
            receipt: const RoomMessageReceipt(
              state: RoomMessageReceiptState.sent,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = _singleGlyphIcon(tester);
      expect(icon.icon, Icons.done);
      expect(icon.size, 12);
      expect(icon.color, tt.textMuted);
      expect(find.bySemanticsLabel('Sent'), findsOneWidget);
    });

    testWidgets('read shows done_all icon, info color, and Read by 2 people semantics',
        (tester) async {
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;

      await tester.pumpWidget(
        _harness(
          RoomMessageReceiptGlyph(
            receipt: const RoomMessageReceipt(
              state: RoomMessageReceiptState.read,
              readerIds: ['reader-a', 'reader-b'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final icon = _singleGlyphIcon(tester);
      expect(icon.icon, Icons.done_all);
      expect(icon.size, 12);
      expect(icon.color, tt.info);
      expect(find.bySemanticsLabel('Read by 2 people'), findsOneWidget);
    });

    testWidgets('read uses Russian semantics for two readers', (tester) async {
      final tt = TenturaTheme.light().extension<TenturaTokens>()!;

      await tester.pumpWidget(
        _harness(
          RoomMessageReceiptGlyph(
            receipt: const RoomMessageReceipt(
              state: RoomMessageReceiptState.read,
              readerIds: ['reader-a', 'reader-b'],
            ),
          ),
          locale: const Locale('ru'),
        ),
      );
      await tester.pumpAndSettle();

      final icon = _singleGlyphIcon(tester);
      expect(icon.icon, Icons.done_all);
      expect(icon.size, 12);
      expect(icon.color, tt.info);
      expect(find.bySemanticsLabel('Прочитали 2 человека'), findsOneWidget);
    });
  });
}
