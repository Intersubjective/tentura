import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// #665: accepting a bud invitation admits the viewer to the Request, and
/// their Activity row then read "Mira accepted your offer" — reversing who
/// did what. The accepted forward row carries `acceptedInvite: true` in its
/// payload when the viewer accepted the author's invitation; the row must
/// say the viewer accepted it. An ordinary accepted offer keeps its sentence.
AttentionReceipt _row(String payload, {String authorName = 'Mira'}) =>
    AttentionReceipt(
      id: 'inbox:b1',
      category: 'coordination',
      kind: 'newRelay',
      priority: 'normal',
      title: 'Move the couch',
      body: '',
      actionUrl: '/#/view?id=b1',
      createdAt: DateTime.utc(2026, 10, 23, 12),
      collapsedCount: 0,
      presentationPayloadJson: payload,
      surface: AttentionSurface.activity,
      itemKind: AttentionItemKind.forward,
      beaconId: 'b1',
      seenAt: DateTime.utc(2026, 10, 23, 12, 5),
      forwardOutcome: AttentionForwardOutcome.helping,
      beaconAuthorId: 'u-mira',
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

const _invitePayload =
    '{"helperStage":"accepted","actorUserId":"u-mira","acceptedInvite":true}';

void main() {
  group('en', () {
    testWidgets('an accepted invitation reads as the viewer accepting', (
      tester,
    ) async {
      await _pump(tester, _row(_invitePayload));

      expect(find.text("You accepted Mira's invitation"), findsOneWidget);
      expect(find.textContaining('accepted your offer'), findsNothing);
    });

    testWidgets('without a readable author it names no one', (tester) async {
      await _pump(tester, _row(_invitePayload, authorName: ''));

      expect(find.text('You accepted the invitation'), findsOneWidget);
      expect(find.text('Your offer was accepted'), findsNothing);
    });

    testWidgets('the Semantics label does not reverse who acted', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _row(_invitePayload));

      expect(
        find.bySemanticsLabel(RegExp('accepted your offer')),
        findsNothing,
      );
      handle.dispose();
    });

    // Guards: an ordinary accepted offer, or a non-true flag, keep the #367
    // sentence that credits the author.
    for (final payload in const [
      '{"helperStage":"accepted","actorUserId":"u-mira"}',
      '{"helperStage":"accepted","actorUserId":"u-mira","acceptedInvite":false}',
      '{"helperStage":"accepted","actorUserId":"u-mira","acceptedInvite":"yes"}',
    ]) {
      testWidgets('payload <$payload> still reads as an accepted offer', (
        tester,
      ) async {
        await _pump(tester, _row(payload));

        expect(find.text('Mira accepted your offer'), findsOneWidget);
      });
    }

    // #665 review: the invite may come from someone other than the author
    // (the payload's inviterId); then the author is not named as inviter.
    testWidgets('an invite from someone else does not name the author', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(
          '{"helperStage":"accepted","acceptedInvite":true,'
          '"inviterId":"u-steward"}',
        ),
      );

      expect(find.text('You accepted the invitation'), findsOneWidget);
      // The row's own author line ("By Mira") stays; only the outcome
      // sentence must not credit Mira with the invite.
      expect(find.textContaining("Mira's invitation"), findsNothing);
    });

    testWidgets('an invite whose inviterId is the author names the author', (
      tester,
    ) async {
      await _pump(
        tester,
        _row(
          '{"helperStage":"accepted","acceptedInvite":true,'
          '"inviterId":"u-mira"}',
        ),
      );

      expect(find.text("You accepted Mira's invitation"), findsOneWidget);
    });

    testWidgets('wrappingUp is unaffected by the invite flag', (tester) async {
      await _pump(
        tester,
        _row('{"helperStage":"wrappingUp","acceptedInvite":true}'),
      );

      expect(
        find.text('Request is in final check — review your collaboration'),
        findsOneWidget,
      );
    });
  });

  group('ru', () {
    testWidgets('an accepted invitation reads as the viewer accepting', (
      tester,
    ) async {
      await _pump(tester, _row(_invitePayload), locale: const Locale('ru'));

      expect(find.text('Вы приняли приглашение от Mira'), findsOneWidget);
      expect(find.textContaining('ваше предложение'), findsNothing);
    });
  });
}
