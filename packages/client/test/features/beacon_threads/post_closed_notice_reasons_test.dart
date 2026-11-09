// The kind-5 `postClosed` notice in a Post room says why the Post ended
// (payload `reason`): budded → «continues in the request» with a link to the
// child, expired / closedByAuthor → their own line with no link. A payload
// without `reason` is a bud (rows written before reasons existed).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_hierarchy_notice.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/fake_app_navigator.dart';

const _expiredLine = 'Срок поста истёк. Пост в архиве.';
const _closedByAuthorLine = 'Автор завершил пост. Пост в архиве.';
const _buddedLine =
    'Пост закрыт. Разговор продолжается в запросе «Велопрогулка в субботу».';

RoomMessage _closedNotice(Map<String, Object?> payload) => RoomMessage(
  id: 'Mclosed',
  beaconId: 'Bpost01',
  authorId: '',
  body: '',
  createdAt: DateTime.utc(2026, 10, 27, 12),
  systemMessageKind: BeaconRoomSystemMessageKind.postClosed,
  systemPayloadJson: jsonEncode(payload),
);

Future<FakeAppNavigator> _pump(
  WidgetTester tester,
  RoomMessage message,
) async {
  final navigator = registerFakeAppNavigator();
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
      home: TenturaResponsiveScope(
        child: Scaffold(body: BeaconHierarchyNotice(message: message)),
      ),
    ),
  );
  await tester.pump();
  return navigator;
}

void main() {
  group('closed Post notice', () {
    testWidgets('budded: continues in the request and opens the child', (
      tester,
    ) async {
      final navigator = await _pump(
        tester,
        _closedNotice({
          'reason': 'budded',
          'childBeaconId': 'Bchild01',
          'title': 'Велопрогулка в субботу',
        }),
      );

      expect(find.text(_buddedLine), findsOneWidget);
      await tester.tap(find.text(_buddedLine));
      await tester.pump();
      expect(navigator.intents, [
        const NavIntent('openBeacon', {'id': 'Bchild01'}),
      ]);
    });

    testWidgets('a payload without a reason reads as a bud', (tester) async {
      final navigator = await _pump(
        tester,
        _closedNotice({
          'childBeaconId': 'Bchild01',
          'title': 'Велопрогулка в субботу',
        }),
      );

      expect(find.text(_buddedLine), findsOneWidget);
      expect(find.text(_expiredLine), findsNothing);
      expect(find.text(_closedByAuthorLine), findsNothing);
      await tester.tap(find.text(_buddedLine));
      await tester.pump();
      expect(navigator.intents, [
        const NavIntent('openBeacon', {'id': 'Bchild01'}),
      ]);
    });

    testWidgets('expired: says the Post ran out and links nowhere', (
      tester,
    ) async {
      final navigator = await _pump(
        tester,
        _closedNotice({'reason': 'expired'}),
      );

      expect(find.text(_expiredLine), findsOneWidget);
      expect(find.text(_closedByAuthorLine), findsNothing);
      expect(find.textContaining('Разговор продолжается'), findsNothing);
      await tester.tap(find.text(_expiredLine), warnIfMissed: false);
      await tester.pump();
      expect(navigator.intents, isEmpty);
    });

    testWidgets('closed by the author: says so and links nowhere', (
      tester,
    ) async {
      final navigator = await _pump(
        tester,
        _closedNotice({'reason': 'closedByAuthor'}),
      );

      expect(find.text(_closedByAuthorLine), findsOneWidget);
      expect(find.text(_expiredLine), findsNothing);
      expect(find.textContaining('Разговор продолжается'), findsNothing);
      await tester.tap(find.text(_closedByAuthorLine), warnIfMissed: false);
      await tester.pump();
      expect(navigator.intents, isEmpty);
    });
  });
}
