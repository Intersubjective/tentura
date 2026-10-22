import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_obligation_block.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

import '../my_work/my_work_test_support.dart';

/// #656: a new question reaches the author as a Questions update (never
/// "New thread message") and opens the Questions screen, not the Chat.
AttentionReceipt _receipt({
  required String id,
  String? coordinationItemId = 'Llobby1',
  String title = 'Ilya',
}) => AttentionReceipt(
  id: id,
  category: 'room',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: title,
  body: 'New message in Questions',
  actionUrl: '/#/beacon/lobby/beacon-1',
  createdAt: DateTime.utc(2026, 10, 23),
  collapsedCount: 1,
  presentationKey: 'room_message_posted',
  presentationPayloadJson: coordinationItemId == null
      ? '{"eventType":"roomMessagePosted","beaconId":"beacon-1"}'
      : '{"eventType":"roomMessagePosted","beaconId":"beacon-1",'
            '"coordinationItemId":"$coordinationItemId"}',
  surface: AttentionSurface.myWork,
  beaconId: 'beacon-1',
  targetEntityId: 'message-1',
  destinationKind: 'beacon_room_message',
  coordinationItemId: coordinationItemId,
);

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  test('a Questions message reads as Questions, in both languages', () {
    for (final l10n in [en, ru]) {
      final scoped = requestScopedEventCopy(
        title: 'Ilya',
        body: 'New message in Questions',
        presentationKey: 'room_message_posted',
        presentationPayloadJson: _receipt(id: 'r').presentationPayloadJson,
        l10n: l10n,
        actorName: 'Ilya',
      );
      expect(scoped.event, l10n.updatesQuestionsMessage);
      expect(scoped.event, isNot(l10n.updatesFallbackTitleRoomMessagePosted));
      // The English push body never leaks in as a quote.
      expect(scoped.excerpt, isEmpty);

      final feed = resolveUpdatesFeedRowCopy(
        title: 'Ilya',
        body: 'New message in Questions',
        presentationKey: 'room_message_posted',
        presentationPayloadJson: _receipt(id: 'r').presentationPayloadJson,
        l10n: l10n,
      );
      expect(feed.headline, 'Ilya');
      expect(feed.body, l10n.updatesQuestionsMessage);
    }
    expect(ru.updatesQuestionsMessage, 'Новое сообщение в вопросах');
  });

  test('a General message keeps its own copy', () {
    final r = _receipt(id: 'g', coordinationItemId: null);
    expect(isQuestionsAttentionReceipt(r), isFalse);
    final scoped = requestScopedEventCopy(
      title: r.title,
      body: 'Hello',
      presentationKey: r.presentationKey,
      presentationPayloadJson: r.presentationPayloadJson,
      l10n: en,
    );
    expect(scoped.event, isNot(en.updatesQuestionsMessage));
  });

  test('a Questions receipt deep-links to the Questions screen', () {
    expect(
      attentionDestination(_receipt(id: 'r')).path,
      '$kPathBeaconLobby/beacon-1',
    );
  });

  Future<AttentionMiniCard> pumpRow(
    WidgetTester tester,
    AttentionReceipt receipt,
    VoidCallback onOpenQuestions,
  ) async {
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
                vm: MyWorkCardViewModel(
                  beaconId: 'beacon-1',
                  role: MyWorkCardRole.authored,
                  kind: MyWorkCardKind.authoredActive,
                  beacon: Beacon.empty.copyWith(id: 'beacon-1', title: 'Move'),
                ),
                obligations: const [],
                optionalEvents: [receipt],
                optionalTotal: 1,
                onOpenQuestions: onOpenQuestions,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<AttentionMiniCard>(find.byType(AttentionMiniCard));
  }

  testWidgets('My Work: tapping a Questions update opens Questions', (
    tester,
  ) async {
    var opened = 0;
    await pumpRow(tester, _receipt(id: 'q'), () => opened++);
    expect(find.textContaining('New message in Questions'), findsOneWidget);
    expect(find.textContaining('New thread message'), findsNothing);
    await tester.tap(find.byType(AttentionMiniCard));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('My Work: a General message row stays as it was (no tap)', (
    tester,
  ) async {
    var opened = 0;
    final card = await pumpRow(
      tester,
      _receipt(id: 'g', coordinationItemId: null),
      () => opened++,
    );
    expect(card.onTap, isNull);
    expect(opened, 0);
  });
}
