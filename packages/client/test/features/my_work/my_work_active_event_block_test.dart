import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _receipt({
  required String id,
  required bool obligation,
  String title = 'Anna',
  String body = 'I can sew',
  String presentationKey = 'help_offer_submitted',
  String? targetEntityId,
}) => AttentionReceipt(
  id: id,
  category: 'coordination',
  kind: 'helpOfferSubmitted',
  priority: 'normal',
  title: title,
  body: body,
  actionUrl: '/#/',
  createdAt: DateTime.utc(2026, 9, 1),
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: '{}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  requiresAction: obligation,
  targetEntityId: targetEntityId,
);

MyWorkCardViewModel _vm() => MyWorkCardViewModel(
  beaconId: 'beacon-1',
  role: MyWorkCardRole.authored,
  kind: MyWorkCardKind.authoredActive,
  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Garden'),
);

Future<void> _pump(
  WidgetTester tester, {
  required List<AttentionReceipt> obligations,
  List<AttentionReceipt> optionalEvents = const [],
  int optionalTotal = 0,
  ValueChanged<String>? onClearEvent,
  void Function(String)? onRespondHelpOffer,
}) async {
  final cubit = MyWorkCubit(userId: 'user-1', myWorkCase: buildTestMyWorkCase());
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
              vm: _vm(),
              obligations: obligations,
              optionalEvents: optionalEvents,
              optionalTotal: optionalTotal,
              onClearEvent: onClearEvent,
              onRespondHelpOffer: onRespondHelpOffer,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('obligations come first, optional lines follow', (tester) async {
    await _pump(
      tester,
      obligations: [
        _receipt(id: 'ob-1', obligation: true, targetEntityId: 'u1'),
      ],
      optionalEvents: [
        _receipt(
          id: 'opt-1',
          obligation: false,
          title: 'Boris',
          body: 'posted an update',
          presentationKey: 'room_message_posted',
        ),
      ],
      optionalTotal: 1,
      onClearEvent: (_) {},
      onRespondHelpOffer: (_) {},
    );

    final cards = tester
        .widgetList<AttentionMiniCard>(find.byType(AttentionMiniCard))
        .toList();
    expect(cards.map((c) => c.receipt.id), ['ob-1', 'opt-1']);
  });

  testWidgets('the optional × is reachable while the block is collapsed', (
    tester,
  ) async {
    final cleared = <String>[];
    await _pump(
      tester,
      obligations: [
        for (var i = 0; i < 3; i++)
          _receipt(id: 'ob-$i', obligation: true, targetEntityId: 'u$i'),
      ],
      optionalEvents: [
        _receipt(
          id: 'opt-1',
          obligation: false,
          title: 'Boris',
          presentationKey: 'room_message_posted',
        ),
      ],
      optionalTotal: 4,
      onClearEvent: cleared.add,
      onRespondHelpOffer: (_) {},
    );

    // No expansion, no navigation: the × is on screen as rendered.
    expect(find.byKey(AttentionMiniCard.dismissKey), findsOneWidget);
    await tester.tap(find.byKey(AttentionMiniCard.dismissKey));
    await tester.pumpAndSettle();
    expect(cleared, ['opt-1']);
  });

  testWidgets('an obligation carries no dismiss control', (tester) async {
    await _pump(
      tester,
      obligations: [
        _receipt(id: 'ob-1', obligation: true, targetEntityId: 'u1'),
      ],
      onClearEvent: (_) {},
      onRespondHelpOffer: (_) {},
    );

    expect(find.byType(AttentionMiniCard), findsOneWidget);
    expect(find.byKey(AttentionMiniCard.dismissKey), findsNothing);
  });
}
