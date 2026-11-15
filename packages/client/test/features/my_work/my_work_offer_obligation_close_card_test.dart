// A help-offer obligation row offers «Respond» only while the offer can still
// be answered; otherwise the row itself carries a close-card action, keyed
// `my-work-obligation-close:<receiptId>`, which settles the receipt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/help_offer_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _offer() => AttentionReceipt(
  id: 'r1',
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'I can sew',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9),
  collapsedCount: 1,
  presentationKey: 'help_offer_submitted',
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  requiresAction: true,
  targetEntityId: 'u1',
);

/// The offerer of the obligation is listed among the Request's help offers
/// only while the offer counts ([HelpOfferStatus.active]).
MyWorkCardViewModel _vm(
  CommitmentStakeState stake,
  BeaconStatus status,
  HelpOfferStatus offerStatus,
) => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(
    id: 'beacon-1',
    title: 'Garden',
    status: status,
    helpOfferUsers: offerStatus == HelpOfferStatus.active
        ? const [Profile(id: 'u1', displayName: 'Anna')]
        : const [],
  ),
  stakeState: stake,
);

Future<StubAttentionRepository> _pump(
  WidgetTester tester,
  CommitmentStakeState stake, [
  BeaconStatus status = BeaconStatus.open,
  HelpOfferStatus offerStatus = HelpOfferStatus.active,
]) async {
  final attention = StubAttentionRepository();
  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(attentionRepository: attention),
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
              vm: _vm(stake, status, offerStatus),
              obligations: [_offer()],
              onRespondHelpOffer: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return attention;
}

final _close = find.byKey(
  const ValueKey<String>('my-work-obligation-close:r1'),
);

/// Only a pending offer on a Request that still takes offers can be answered
/// from the card; every other state offers no answering action.
bool _canAnswer(
  CommitmentStakeState stake,
  BeaconStatus status,
  HelpOfferStatus offerStatus,
) =>
    status.isOpenFamily &&
    offerStatus == HelpOfferStatus.active &&
    switch (stake) {
      CommitmentStakeState.none || CommitmentStakeState.offered => true,
      CommitmentStakeState.acknowledged ||
      CommitmentStakeState.softened ||
      CommitmentStakeState.exited ||
      CommitmentStakeState.released => false,
    };

void main() {
  late String respond;

  setUp(() => respond = lookupL10n(const Locale('en')).myWorkObligationRespond);

  testWidgets('an admitted offer shows close-card instead of Respond', (
    tester,
  ) async {
    await _pump(tester, CommitmentStakeState.acknowledged);

    expect(find.text(respond), findsNothing);
    expect(_close, findsOneWidget);
  });

  testWidgets('a pending offer on a Request that no longer takes offers shows '
      'close-card instead of Respond', (tester) async {
    await _pump(tester, CommitmentStakeState.offered, BeaconStatus.closed);

    expect(find.text(respond), findsNothing);
    expect(_close, findsOneWidget);
  });

  testWidgets('close-card settles the obligation receipt by id', (
    tester,
  ) async {
    final attention = await _pump(tester, CommitmentStakeState.acknowledged);

    await tester.tap(_close);
    await tester.pumpAndSettle();

    expect(attention.settleCalls, ['r1']);
  });

  testWidgets('a pending offer on an open Request still offers Respond', (
    tester,
  ) async {
    await _pump(tester, CommitmentStakeState.offered);

    expect(find.widgetWithText(FilledButton, respond), findsOneWidget);
  });

  testWidgets('a withdrawn offer shows close-card instead of Respond', (
    tester,
  ) async {
    await _pump(
      tester,
      CommitmentStakeState.offered,
      BeaconStatus.open,
      HelpOfferStatus.inactive,
    );

    expect(find.text(respond), findsNothing);
    expect(_close, findsOneWidget);
  });

  // Built from the enums' .values: a new value without a rule fails here.
  for (final stake in CommitmentStakeState.values) {
    for (final status in BeaconStatus.values) {
      for (final offerStatus in HelpOfferStatus.values) {
        testWidgets(
          'stake ${stake.name}, ${offerStatus.name} offer on a ${status.name} '
          'Request: Respond only when it can be answered, close-card otherwise',
          (tester) async {
            await _pump(tester, stake, status, offerStatus);

            final answerable = _canAnswer(stake, status, offerStatus);
            expect(find.text(respond).evaluate().isNotEmpty, answerable);
            expect(_close.evaluate().isNotEmpty, !answerable);
          },
        );
      }
    }
  }
}
