import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #507 / #601: a steward can accept a helper's offer, and the helper's
/// Activity row still credited the Request's author ("Tab QA accepted your
/// offer"). The accepted forward row carries the acceptor in its payload as
/// `actorUserId`; when that is not the author, the row must not name the
/// author as the one who accepted. It still says the offer was accepted and
/// keeps the role. An absent acceptor, or the author, keeps today's sentence.
AttentionReceipt _row(String payload) => AttentionReceipt(
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
  beaconAuthorId: 'u-author',
  beaconAuthorName: 'Tab QA',
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

const _stewardPayload =
    '{"helperStage":"accepted","roleLabel":"Driver","actorUserId":"u-steward"}';

void main() {
  group('en', () {
    testWidgets('a steward accept does not credit the author', (tester) async {
      await _pump(tester, _row(_stewardPayload));

      expect(find.textContaining('Tab QA accepted'), findsNothing);
      // Still an acceptance, with its role, and not the old sentence.
      expect(
        _textWhere(
          (t) =>
              t.contains('accepted') &&
              t.contains('Driver') &&
              !t.contains('Tab QA'),
        ),
        findsOneWidget,
      );
      expect(find.text('You offered help'), findsNothing);
    });

    testWidgets('the Semantics label does not credit the author either', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _row(_stewardPayload));

      expect(find.bySemanticsLabel(RegExp('Tab QA accepted')), findsNothing);
      handle.dispose();
    });

    // Guards: the author as acceptor, or no acceptor on record, keep the
    // #367 sentence that names the author.
    for (final payload in const [
      '{"helperStage":"accepted","roleLabel":"Driver","actorUserId":"u-author"}',
      '{"helperStage":"accepted","roleLabel":"Driver"}',
      '{"helperStage":"accepted","roleLabel":"Driver","actorUserId":""}',
    ]) {
      testWidgets('payload <$payload> still names the author', (tester) async {
        await _pump(tester, _row(payload));

        expect(
          find.text('Tab QA accepted your offer · role: Driver'),
          findsOneWidget,
        );
      });
    }

    testWidgets('wrappingUp is unaffected by a steward acceptor', (
      tester,
    ) async {
      await _pump(
        tester,
        _row('{"helperStage":"wrappingUp","actorUserId":"u-steward"}'),
      );

      expect(
        find.text('Request is in final check — review your collaboration'),
        findsOneWidget,
      );
    });
  });

  group('ru', () {
    testWidgets('a steward accept does not credit the author', (tester) async {
      await _pump(tester, _row(_stewardPayload), locale: const Locale('ru'));

      expect(
        _textWhere((t) => t.contains('Driver') && !t.contains('Tab QA')),
        findsOneWidget,
      );
      expect(
        _textWhere((t) => t.contains('Driver') && t.contains('Tab QA')),
        findsNothing,
      );
      expect(find.text('Вы предложили помощь'), findsNothing);
    });
  });
}
