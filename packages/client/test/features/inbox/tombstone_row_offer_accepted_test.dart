import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #367: the helper's Activity row for a Request whose author accepted their
/// offer said "You offered help" forever, and nothing said the Request had
/// entered its final check. The row stays `helping` on the wire (old apps
/// keep their sentence); its payload carries `helperStage` ('accepted' |
/// 'wrappingUp') and `roleLabel`, and the row says who accepted (the
/// Request's author), with the role, and later that it is in final check.
AttentionReceipt _row({
  String payload = '{}',
  String? authorName = 'Tab QA',
}) => AttentionReceipt(
  id: 'inbox:b1',
  category: 'coordination',
  kind: 'newRelay',
  priority: 'normal',
  title: 'Move the couch',
  body: '',
  actionUrl: '/#/view?id=b1',
  createdAt: DateTime.utc(2026, 10, 14, 12),
  collapsedCount: 0,
  presentationPayloadJson: payload,
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.forward,
  beaconId: 'b1',
  seenAt: DateTime.utc(2026, 10, 14, 12, 5),
  forwardOutcome: AttentionForwardOutcome.helping,
  beaconAuthorId: authorName == null ? null : 'u-author',
  beaconAuthorName: authorName,
);

Future<void> _pump(
  WidgetTester tester,
  AttentionReceipt receipt, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 360,
                child: TombstoneRow(
                  receipt: receipt,
                  onOpenBeacon: () {},
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _textWhere(bool Function(String text) matches) => find.byWidgetPredicate(
  (widget) => widget is Text && widget.data != null && matches(widget.data!),
);

void main() {
  group('en', () {
    testWidgets('accepted names the author and the role', (tester) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"accepted","roleLabel":"Driver"}'),
      );

      expect(
        find.text('Tab QA accepted your offer · role: Driver'),
        findsOneWidget,
      );
      expect(find.text('You offered help'), findsNothing);
    });

    testWidgets('accepted without a role drops the role part', (tester) async {
      await _pump(tester, _row(payload: '{"helperStage":"accepted"}'));

      expect(find.text('Tab QA accepted your offer'), findsOneWidget);
      expect(find.textContaining('role:'), findsNothing);
    });

    testWidgets('an empty role is no role', (tester) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"accepted","roleLabel":""}'),
      );

      expect(find.text('Tab QA accepted your offer'), findsOneWidget);
      expect(find.textContaining('role:'), findsNothing);
    });

    testWidgets('accepted with no readable author still says so', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"accepted"}', authorName: null),
      );

      expect(find.text('Your offer was accepted'), findsOneWidget);
    });

    testWidgets('wrappingUp asks the helper to review', (tester) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"wrappingUp","roleLabel":"Driver"}'),
      );

      expect(
        find.text('Request is in final check — review your collaboration'),
        findsOneWidget,
      );
      expect(find.text('You offered help'), findsNothing);
    });

    // Guards: no stage, an unknown stage or a broken payload keep today's
    // sentence — never an "accepted" the server did not say.
    for (final payload in const [
      '{}',
      '{"roleLabel":"Driver"}',
      '{"helperStage":"foo","roleLabel":"Driver"}',
      '{"helperStage":',
      '',
    ]) {
      testWidgets('helping with payload <$payload> reads You offered help', (
        tester,
      ) async {
        await _pump(tester, _row(payload: payload));

        expect(find.text('You offered help'), findsOneWidget);
        expect(find.textContaining('accepted'), findsNothing);
        expect(find.textContaining('final check'), findsNothing);
      });
    }
  });

  group('ru', () {
    testWidgets('accepted is translated and keeps the name and the role', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"accepted","roleLabel":"Driver"}'),
        locale: const Locale('ru'),
      );

      expect(
        _textWhere((t) => t.contains('Tab QA') && t.contains('Driver')),
        findsOneWidget,
      );
      expect(find.textContaining('accepted your offer'), findsNothing);
      expect(find.text('Вы предложили помощь'), findsNothing);
    });

    testWidgets('wrappingUp is translated in the final-check words', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(payload: '{"helperStage":"wrappingUp"}'),
        locale: const Locale('ru'),
      );

      expect(
        _textWhere((t) => t.toLowerCase().contains('итог')),
        findsOneWidget,
      );
      expect(find.textContaining('final check'), findsNothing);
      expect(find.text('Вы предложили помощь'), findsNothing);
    });
  });
}
