// #725: declining an author invitation went through three wordings — the
// button "Can't make it", the dialog "Can't help?", then the Activity row
// "You dismissed it / Restore" — and the Request page showed no trace of it.
// The invitation path now says "can't make it" throughout ("You said you
// can't make it", no Undo since V1-B); a dismissed forward keeps "dismissed" (#485). The
// Request page says so above Offer help.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/inbox/ui/widget/tombstone_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

AttentionReceipt _notInterested(String payload) => AttentionReceipt(
  id: 'inbox:b1',
  category: 'coordination',
  kind: 'newRelay',
  priority: 'normal',
  title: 'Garden cleanup Saturday',
  body: '',
  actionUrl: '/#/view?id=b1',
  createdAt: DateTime.utc(2026, 10, 24, 18),
  collapsedCount: 0,
  presentationPayloadJson: payload,
  surface: AttentionSurface.activity,
  itemKind: AttentionItemKind.forward,
  beaconId: 'b1',
  seenAt: DateTime.utc(2026, 10, 24, 18, 5),
  forwardOutcome: AttentionForwardOutcome.notInterested,
  beaconAuthorId: 'u-alice',
  beaconAuthorName: 'Alice',
);

const _declinedInvite = '{"declinedInvite":true}';

Widget _app(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(360, 640)),
    child: TenturaResponsiveScope(child: Scaffold(body: home)),
  ),
);

Future<void> _pumpRow(
  WidgetTester tester,
  AttentionReceipt receipt, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    _app(
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 360,
          child: TombstoneRow(
            receipt: receipt,
            onOpenBeacon: () {},
            onDismiss: () {},
            onRestore: () {},
          ),
        ),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

const _author = Profile(id: 'u-alice', displayName: 'Alice');
const _carol = Profile(id: 'u-carol', displayName: 'Carol');

BeaconViewState _page({
  InboxItemStatus? inboxStatus = InboxItemStatus.rejected,
  BeaconStatus status = BeaconStatus.open,
  Profile viewer = _carol,
  List<TimelineHelpOffer> helpOffers = const [],
}) => BeaconViewState(
  beacon: Beacon.empty.copyWith(
    id: 'b1',
    status: status,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    author: _author,
  ),
  myProfile: viewer,
  inboxStatus: inboxStatus,
  helpOffers: helpOffers,
);

void main() {
  group('the Activity row after «Can\u2019t make it»', () {
    // V1-B (Vadim, 2026-10-27): Undo only re-pinned the row and never
    // brought the invitation back, so a declined invitation offers none;
    // the Request page still says the viewer can offer help.
    testWidgets('says the viewer can\u2019t make it, with no Undo', (
      tester,
    ) async {
      await _pumpRow(tester, _notInterested(_declinedInvite));

      expect(find.text("You said you can't make it"), findsOneWidget);
      expect(find.text('You dismissed it'), findsNothing);
      expect(find.byKey(TombstoneRow.restoreKey), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Restore'), findsNothing);
      // The private × stays.
      expect(find.byKey(TombstoneRow.dismissKey), findsOneWidget);
    });

    testWidgets('in Russian too', (tester) async {
      await _pumpRow(
        tester,
        _notInterested(_declinedInvite),
        locale: const Locale('ru'),
      );

      expect(find.text('Вы ответили «Не смогу»'), findsOneWidget);
      expect(find.text('Отменить'), findsNothing);
      expect(find.text('Вернуть'), findsNothing);
      expect(find.text('Вы убрали'), findsNothing);
    });

    // Guard: a dismissed forward keeps its #485 words.
    for (final payload in const ['{}', '{"declinedInvite":false}']) {
      testWidgets('a dismissed forward <$payload> still says dismissed', (
        tester,
      ) async {
        await _pumpRow(tester, _notInterested(payload));

        expect(find.text('You dismissed it'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(TombstoneRow.restoreKey),
            matching: find.text('Restore'),
          ),
          findsOneWidget,
        );
        expect(find.text("You said you can't make it"), findsNothing);
      });
    }
  });

  group('the decline dialog on an invitation', () {
    testWidgets('keeps the button\u2019s words', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showInviteDeclineDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("Can't make it?"), findsOneWidget);
      expect(find.text("Can't help?"), findsNothing);
    });

    test('in Russian it asks «Не сможете?»', () {
      expect(L10nRu().inviteDeclineDialogTitle, 'Не сможете?');
    });
  });

  group('the Request page after «Can\u2019t make it»', () {
    test('says so above Offer help', () {
      expect(
        beaconShowcaseDeclinedText(L10nEn(), _page()),
        "You said you can't make it. You can still offer help.",
      );
      expect(
        beaconShowcaseDeclinedText(L10nRu(), _page()),
        'Вы ответили «Не смогу». Помощь всё ещё можно предложить.',
      );
    });

    test('says nothing when the viewer did not decline', () {
      for (final status in [
        null,
        InboxItemStatus.needsMe,
        InboxItemStatus.watching,
      ]) {
        expect(
          beaconShowcaseDeclinedText(L10nEn(), _page(inboxStatus: status)),
          isNull,
          reason: '$status',
        );
      }
    });

    test('says nothing once they offered help after all', () {
      final state = _page(
        helpOffers: [
          TimelineHelpOffer(
            user: _carol,
            message: 'I can come after all',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(beaconShowcaseDeclinedText(L10nEn(), state), isNull);
    });

    test('says nothing on a finished Request', () {
      for (final status in [BeaconStatus.closed, BeaconStatus.cancelled]) {
        expect(
          beaconShowcaseDeclinedText(L10nEn(), _page(status: status)),
          isNull,
        );
      }
    });
  });
}
