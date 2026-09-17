import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'my_work_test_support.dart';

AttentionReceipt _offer({
  required String id,
  required String offererId,
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'Offered help',
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

MyWorkCardViewModel _vm({
  bool showReviewCta = false,
  bool showReviewHelpOffersCta = false,
}) => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Garden'),
  showReviewCta: showReviewCta,
  showReviewHelpOffersCta: showReviewHelpOffersCta,
);

Future<MyWorkCubit> _pumpBlock(
  WidgetTester tester, {
  required List<AttentionReceipt> obligations,
  MyWorkCardViewModel? vm,
  VoidCallback? onReviewContributions,
  void Function(String)? onRespondHelpOffer,
  VoidCallback? onReviewHelpOffers,
  bool suppressReviewHelpOffersFallback = false,
  bool suppressReviewFallback = false,
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
              onReviewContributions: onReviewContributions,
              onRespondHelpOffer: onRespondHelpOffer,
              onReviewHelpOffers: onReviewHelpOffers,
              suppressReviewHelpOffersFallback:
                  suppressReviewHelpOffersFallback,
              suppressReviewFallback: suppressReviewFallback,
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
  testWidgets('empty obligations still show review fallback CTA', (tester) async {
    await _pumpBlock(
      tester,
      obligations: const [],
      vm: _vm(showReviewCta: true),
      onReviewContributions: () {},
    );

    expect(find.text('Review'), findsOneWidget);
  });

  testWidgets('Respond and Done are independent hit targets', (tester) async {
    var respondCount = 0;
    await _pumpBlock(
      tester,
      obligations: [_offer(id: 'r1', offererId: 'u1')],
      onRespondHelpOffer: (_) => respondCount++,
    );

    final respond = find.widgetWithText(TenturaTextAction, 'Respond');
    final done = find.bySemanticsIdentifier(TestIds.myWorkObligationDone('r1'));
    expect(respond, findsOneWidget);
    expect(done, findsOneWidget);

    expect(tester.getSize(respond).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(done).height, greaterThanOrEqualTo(48));

    await tester.tap(respond);
    await tester.pump();
    expect(respondCount, 1);
  });

  testWidgets('Respond does not require opening the Request', (tester) async {
    var respondCount = 0;
    var reviewCount = 0;
    await _pumpBlock(
      tester,
      obligations: [_offer(id: 'r1', offererId: 'u1')],
      onRespondHelpOffer: (_) => respondCount++,
      onReviewContributions: () => reviewCount++,
    );

    await tester.tap(find.text('Respond'));
    await tester.pump();
    expect(respondCount, 1);
    expect(reviewCount, 0);
  });

  testWidgets('Review sub-card primary opens review callback', (tester) async {
    var reviewCount = 0;
    await _pumpBlock(
      tester,
      obligations: [
        AttentionReceipt(
          id: 'rev-1',
          category: 'coordination',
          kind: 'reviewOpened',
          priority: 'normal',
          title: 'Review',
          body: 'Contributions ready',
          actionUrl: '/#/',
          createdAt: DateTime.utc(2026, 9, 1),
          collapsedCount: 1,
          presentationKey: 'review_opened',
          presentationPayloadJson: '{}',
          surface: AttentionSurface.myWork,
          beaconId: 'beacon-1',
          requiresAction: true,
        ),
      ],
      onReviewContributions: () => reviewCount++,
    );

    await tester.tap(find.text('Review').first);
    await tester.pump();
    expect(reviewCount, 1);
  });

  testWidgets('Review sub-card has Review CTA but no Done', (tester) async {
    await _pumpBlock(
      tester,
      obligations: [
        AttentionReceipt(
          id: 'rev-1',
          category: 'coordination',
          kind: 'reviewOpened',
          priority: 'normal',
          title: 'Review',
          body: 'Contributions ready',
          actionUrl: '/#/',
          createdAt: DateTime.utc(2026, 9, 1),
          collapsedCount: 1,
          presentationKey: 'review_opened',
          presentationPayloadJson: '{}',
          surface: AttentionSurface.myWork,
          beaconId: 'beacon-1',
          requiresAction: true,
        ),
      ],
      onReviewContributions: () {},
    );

    expect(find.text('Review'), findsWidgets);
    expect(
      find.bySemanticsIdentifier(TestIds.myWorkObligationDone('rev-1')),
      findsNothing,
    );
  });

  test('block visible when only showReviewCta and no live receipts', () {
    expect(
      myWorkObligationBlockVisible(
        vm: _vm(showReviewCta: true),
        obligations: const [],
      ),
      isTrue,
    );
    expect(
      myWorkObligationBlockVisible(
        vm: _vm(),
        obligations: const [],
      ),
      isFalse,
    );
  });
}
