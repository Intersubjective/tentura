import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_indicators.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_card_attention_indicators.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _receipt({
  required String id,
  required bool obligation,
  String presentationKey = 'help_offer_submitted',
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: 'Anna',
  body: 'I can sew',
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'b1',
  requiresAction: obligation,
  targetEntityId: obligation ? 'u1' : null,
);

MyWorkCardViewModel _vm() => MyWorkCardViewModel(
  beaconId: 'b1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'b1', title: 'Garden'),
);

/// Mounts the indicators and the block the card mounts, off one cubit — the
/// pairing the card itself makes.
Future<MyWorkCubit> _pump(
  WidgetTester tester, {
  required MyWorkBeaconAttention? attention,
}) async {
  final attentionRepo = StubAttentionRepository()
    ..myWorkAttentionResult = [?attention];
  final repo = FakeMyWorkRepository()
    ..initResult = (
      authoredNonArchived: [Beacon.empty.copyWith(id: 'b1')],
      helpOfferedNonArchived: const [],
      obligationBeacons: const [],
      archivedCountHint: 0,
    );
  final cubit = MyWorkCubit(
    userId: 'user-1',
    myWorkCase: buildTestMyWorkCase(
      repo: repo,
      attentionRepository: attentionRepo,
    ),
  );
  addTearDown(cubit.close);
  await cubit.stream.firstWhere((s) => s.attentionLoaded);

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
            child: BlocBuilder<MyWorkCubit, MyWorkState>(
              builder: (context, state) {
                final entry = state.attentionByBeacon['b1'];
                return Column(
                  children: [
                    MyWorkCardAttentionIndicators(vm: _vm()),
                    MyWorkObligationBlock(
                      vm: _vm(),
                      obligations:
                          entry?.liveObligations ??
                          const <AttentionReceipt>[],
                      optionalEvents: <AttentionReceipt>[?entry?.latestUnseen],
                      optionalTotal: entry?.unseenCount ?? 0,
                      onClearEvent: (receiptId) => unawaited(
                        context.read<MyWorkCubit>().clearOptionalEvent(
                          'b1',
                          receiptId,
                        ),
                      ),
                      onRespondHelpOffer: (_) {},
                    ),
                  ],
                );
              },
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
  testWidgets('dot and count are both present, neither hiding the other', (
    tester,
  ) async {
    await _pump(
      tester,
      attention: MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 3,
        latestUnseen: _receipt(
          id: 'opt',
          obligation: false,
          presentationKey: 'room_message_posted',
        ),
        liveObligations: [
          _receipt(id: 'o1', obligation: true),
          _receipt(id: 'o2', obligation: true),
        ],
      ),
    );

    expect(find.byKey(RequestAttentionIndicators.dotKey), findsOneWidget);
    expect(find.byKey(RequestAttentionIndicators.countKey), findsOneWidget);
    // The number is the obligations, not the optional events.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a lit dot always has the row it counts on the card', (
    tester,
  ) async {
    await _pump(
      tester,
      attention: MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 1,
        latestUnseen: _receipt(
          id: 'opt',
          obligation: false,
          presentationKey: 'room_message_posted',
        ),
      ),
    );

    expect(find.byKey(RequestAttentionIndicators.dotKey), findsOneWidget);
    expect(find.byType(AttentionMiniCard), findsOneWidget);
  });

  testWidgets('a server total with no row to show lights nothing', (
    tester,
  ) async {
    // The lit-but-empty card, stated as the defect it is: the total says four
    // and the card can render none of them.
    await _pump(
      tester,
      attention: const MyWorkBeaconAttention(beaconId: 'b1', unseenCount: 4),
    );

    expect(find.byKey(RequestAttentionIndicators.dotKey), findsNothing);
    expect(find.byKey(RequestAttentionIndicators.countKey), findsNothing);
    expect(find.byType(AttentionMiniCard), findsNothing);
  });

  testWidgets('clearing the last optional row puts the dot out', (
    tester,
  ) async {
    await _pump(
      tester,
      attention: MyWorkBeaconAttention(
        beaconId: 'b1',
        unseenCount: 1,
        latestUnseen: _receipt(
          id: 'opt',
          obligation: false,
          presentationKey: 'room_message_posted',
        ),
        liveObligations: [_receipt(id: 'o1', obligation: true)],
      ),
    );
    expect(find.byKey(RequestAttentionIndicators.dotKey), findsOneWidget);

    await tester.tap(find.byKey(AttentionMiniCard.dismissKey));
    await tester.pumpAndSettle();

    expect(find.byKey(RequestAttentionIndicators.dotKey), findsNothing);
    // The obligation survived it: the count is still there.
    expect(find.byKey(RequestAttentionIndicators.countKey), findsOneWidget);
  });
}
