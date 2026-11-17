// The Updates/Activity mini card for «Who'll take it?» baton receipts: a
// partner invitation, the partner's answer (accepted / declined) and a pair
// taking it each read as one named line in the viewer's language, never the
// server title or a payload candidate list, and a tap opens the row once.
// A pair-taken line names the partner from the actor profiles the screen
// already holds; without a name it stays the solo «You took it».

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/destination_map.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/activity_event_subcard_block.dart';
import 'package:tentura/features/inbox/ui/widget/attention_mini_card.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../support/fake_app_navigator.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _anna = Profile(id: 'u-anna', displayName: 'Anna');
const _xenia = Profile(id: 'u-xenia', displayName: 'Xenia');

AttentionReceipt _receipt(
  String type,
  int beaconKind, {
  String actorId = 'u-anna',
  Map<String, Object?> payload = const {},
}) => AttentionReceipt(
  id: 'receipt-$type',
  category: 'coordination',
  kind: type,
  priority: 'normal',
  title: 'Server English title',
  body: 'Carry the boxes',
  actionUrl: '/beacon/view/B1?tab=threads&messageId=M1',
  createdAt: DateTime.utc(2026, 10, 5, 12),
  collapsedCount: 1,
  presentationPayloadJson: jsonEncode({
    'eventType': type,
    'personal': type != 'batonTaken',
    'excerpt': 'Carry the boxes',
    'candidates': [
      {'userId': 'other-candidate', 'title': 'Private candidate'},
    ],
    ...payload,
  }),
  presentationKey: switch (type) {
    'batonPartnerAsked' => 'baton_partner_asked',
    'batonPartnerAnswered' => 'baton_partner_answered',
    _ => 'baton_taken',
  },
  actorUserId: actorId,
  beaconId: 'B1',
  beaconKind: beaconKind,
  destinationKind: 'beacon_room_message',
  targetEntityId: 'M1',
  surface: AttentionSurface.activity,
);

Future<void> _pump(
  WidgetTester tester,
  AttentionReceipt receipt, {
  required String locale,
  Map<String, Profile> actors = const {'u-anna': _anna, 'u-xenia': _xenia},
}) async {
  const size = Size(600, 900);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    BlocProvider<ScreenCubit>.value(
      value: ScreenCubit.local(FakeUiEffectPort()),
      child: MaterialApp(
        locale: Locale(locale),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: ActivityEventSubcardBlock(
                eventTotal: 1,
                eventsPreview: [receipt],
                actors: actors,
                // The row opens like the Activity stream opens it: through the
                // app navigator.
                onEventTap: (r) => GetIt.I<AppNavigator>().openFromUpdate(r),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  late FakeAppNavigator navigator;
  setUp(() => navigator = registerFakeAppNavigator());
  tearDown(() => GetIt.I.reset());

  // (name, receipt for a beacon kind, EN headline, RU headline)
  final cases = <(String, AttentionReceipt Function(int), String, String)>[
    (
      'partner asked',
      (k) => _receipt('batonPartnerAsked', k),
      'Anna wants to take it on together with you',
      'Anna предлагает взяться вместе',
    ),
    (
      'partner answered accepted',
      (k) => _receipt(
        'batonPartnerAnswered',
        k,
        actorId: 'u-xenia',
        payload: {'accepted': true},
      ),
      'Xenia will take it on with you',
      'Xenia возьмётся вместе с вами',
    ),
    (
      'partner answered declined',
      (k) => _receipt(
        'batonPartnerAnswered',
        k,
        actorId: 'u-xenia',
        payload: {'accepted': false},
      ),
      "Xenia can't join you. Answer again",
      'Xenia не сможет присоединиться. Ответьте ещё раз',
    ),
    (
      'pair taken',
      (k) => _receipt(
        'batonTaken',
        k,
        actorId: 'author',
        payload: {'withUserId': 'u-xenia'},
      ),
      'You and Xenia took it: Carry the boxes',
      'Вы и Xenia взялись: Carry the boxes',
    ),
  ];

  for (final locale in ['en', 'ru']) {
    for (final beaconKind in [0, 1]) {
      for (final (name, build, en, ru) in cases) {
        testWidgets(
          '$name card reads its named line and opens once $locale '
          'host=$beaconKind',
          (tester) async {
            final receipt = build(beaconKind);
            await _pump(tester, receipt, locale: locale);

            expect(find.byType(AttentionMiniCard), findsOneWidget);
            final line = find.textContaining(
              locale == 'ru' ? ru : en,
              findRichText: true,
            );
            expect(line, findsOneWidget);
            expect(find.textContaining('Server English title'), findsNothing);
            expect(find.textContaining('Private candidate'), findsNothing);
            expect(find.textContaining('other-candidate'), findsNothing);

            await tester.tap(line);
            await tester.pump(const Duration(milliseconds: 400));
            expect(navigator.named('openFromUpdate'), hasLength(1));
            final destination = attentionDestination(
              navigator.openedReceipts.single,
            );
            expect(
              destination.path,
              beaconKind == 1 ? '$kPathPostView/B1' : '$kPathBeaconView/B1',
            );
            expect(
              destination.queryParameters[kQueryBeaconViewTab],
              kBeaconViewTabThreads,
            );
            expect(destination.queryParameters[kQueryMessageId], 'M1');
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final locale in ['en', 'ru']) {
    final solo = locale == 'ru'
        ? 'Вы взялись: Carry the boxes'
        : 'You took it: Carry the boxes';

    testWidgets('taken without a partner id reads the solo line $locale', (
      tester,
    ) async {
      await _pump(
        tester,
        _receipt('batonTaken', 0, actorId: 'author'),
        locale: locale,
        // Xenia is known to the screen, but the receipt does not name her.
      );

      expect(find.textContaining(solo, findRichText: true), findsOneWidget);
      expect(find.textContaining('Xenia'), findsNothing);
    });

    testWidgets('taken with a partner nobody can name reads the solo line '
        '$locale', (tester) async {
      await _pump(
        tester,
        _receipt(
          'batonTaken',
          0,
          actorId: 'author',
          payload: {'withUserId': 'u-unknown'},
        ),
        locale: locale,
        actors: const {'u-anna': _anna},
      );

      expect(find.textContaining(solo, findRichText: true), findsOneWidget);
      expect(find.textContaining('u-unknown'), findsNothing);
      expect(find.textContaining(' and '), findsNothing);
      expect(find.textContaining(' и '), findsNothing);
    });
  }
}
