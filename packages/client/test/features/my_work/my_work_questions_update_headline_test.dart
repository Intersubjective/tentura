import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'my_work_test_support.dart';

AttentionReceipt _question({
  required String asker,
  required DateTime createdAt,
}) => AttentionReceipt(
  id: 'question-$asker',
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: asker,
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/request-1',
  createdAt: createdAt,
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: jsonEncode({
    'eventType': 'roomMessagePosted',
    'beaconId': 'request-1',
    'coordinationItemId': 'questions-1',
    'actorUserId': asker.toLowerCase(),
    'actorName': asker,
  }),
  surface: AttentionSurface.myWork,
  beaconId: 'request-1',
  actorUserId: asker.toLowerCase(),
  targetEntityId: 'message-$asker',
  destinationKind: 'beacon_room_message',
  coordinationItemId: 'questions-1',
);

Future<void> _pumpUpdates(
  WidgetTester tester,
  List<AttentionReceipt> newestFirst,
) async {
  final cubit = MyWorkCubit(
    userId: 'alice',
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
              vm: MyWorkCardViewModel(
                beaconId: 'request-1',
                role: MyWorkCardRole.authored,
                kind: MyWorkCardKind.authoredActive,
                // Askers need not be admitted helpers or help offerers.
                beacon: Beacon.empty.copyWith(
                  id: 'request-1',
                  title: 'Move the garden shed',
                  author: const Profile(id: 'alice', displayName: 'Alice'),
                ),
              ),
              obligations: const [],
              optionalEvents: newestFirst,
              optionalTotal: newestFirst.length,
              onOpenQuestions: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Requests card Questions update headline', () {
    final now = DateTime.utc(2026, 10, 29, 12);

    testWidgets('names the asker when Bob posts a question', (tester) async {
      await _pumpUpdates(tester, [_question(asker: 'Bob', createdAt: now)]);

      expect(tester.takeException(), isNull);
      final updateRow = find.byType(AttentionMiniCard);
      expect(updateRow, findsOneWidget);
      expect(
        find.descendant(
          of: updateRow,
          matching: find.textContaining('New message in Questions'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: updateRow,
          matching: find.text('Bob · New message in Questions'),
        ),
        findsOneWidget,
      );
    });

    testWidgets("names Carol when her question is newer than Bob's", (
      tester,
    ) async {
      final bob = _question(
        asker: 'Bob',
        createdAt: now.subtract(const Duration(minutes: 1)),
      );
      await _pumpUpdates(tester, [bob]);
      expect(find.textContaining('New message in Questions'), findsOneWidget);

      // A refresh delivers the newest question first, as on the card.
      await _pumpUpdates(tester, [
        _question(asker: 'Carol', createdAt: now),
        bob,
      ]);

      expect(tester.takeException(), isNull);
      final updateRow = find.byType(AttentionMiniCard);
      expect(updateRow, findsOneWidget);
      expect(
        find.descendant(
          of: updateRow,
          matching: find.textContaining('New message in Questions'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: updateRow,
          matching: find.text('Carol · New message in Questions'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: updateRow, matching: find.textContaining('Bob')),
        findsNothing,
      );
    });
  });
}
