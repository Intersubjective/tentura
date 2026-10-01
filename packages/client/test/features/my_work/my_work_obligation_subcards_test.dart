import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _offer({
  required String id,
  required String offererId,
  String body = 'I can sew',
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  requiresAction: true,
  targetEntityId: offererId,
);

MyWorkCardViewModel _vm({bool showReviewHelpOffersCta = false}) =>
    MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Garden'),
  showReviewHelpOffersCta: showReviewHelpOffersCta,
);

Future<MyWorkCubit> _pumpBlock(
  WidgetTester tester, {
  required List<AttentionReceipt> obligations,
  MyWorkCardViewModel? vm,
  void Function(String)? onRespondHelpOffer,
  VoidCallback? onReviewHelpOffers,
  bool suppressReviewHelpOffersFallback = false,
}) async {
  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(),
  );
  addTearDown(cubit.close);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: BlocProvider<MyWorkCubit>.value(
            value: cubit,
            child: MyWorkObligationBlock(
              vm: vm ?? _vm(),
              obligations: obligations,
              onRespondHelpOffer: onRespondHelpOffer,
              onReviewHelpOffers: onReviewHelpOffers,
              suppressReviewHelpOffersFallback:
                  suppressReviewHelpOffersFallback,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cubit;
}

void main() {
  // U15 (was: CHANGES IN U07b): Respond is the only control on a help-offer
  // obligation. Generic Done is gone from the client because the server
  // refuses it (U07b2) and because nothing here can be honestly resolved by
  // acknowledgment (D04, owner decision C).
  testWidgets('Respond is the whole control set on a help-offer obligation', (
    tester,
  ) async {
    var respondCount = 0;
    await _pumpBlock(
      tester,
      obligations: [_offer(id: 'r1', offererId: 'u1')],
      onRespondHelpOffer: (_) => respondCount++,
    );

    expect(find.textContaining('I can sew'), findsOneWidget);

    // The group header names the event once; the row's CTA shares its line.
    expect(find.text('Offered help · 1'), findsOneWidget);
    final respond = find.widgetWithText(FilledButton, 'Respond');
    expect(respond, findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.widgetWithText(TenturaTextAction, 'Done'), findsNothing);

    expect(tester.getSize(respond).height, greaterThanOrEqualTo(48));

    await tester.tap(respond);
    await tester.pump();
    expect(respondCount, 1);
  });

  testWidgets('Respond does not require opening the Request', (tester) async {
    var respondCount = 0;
    await _pumpBlock(
      tester,
      obligations: [_offer(id: 'r1', offererId: 'u1')],
      onRespondHelpOffer: (_) => respondCount++,
    );

    await tester.tap(find.text('Respond'));
    await tester.pump();
    expect(respondCount, 1);
  });

  test('block hidden when there are no live receipts', () {
    expect(
      myWorkObligationBlockVisible(
        vm: _vm(),
        obligations: const [],
      ),
      isFalse,
    );
  });
}
