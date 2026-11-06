// #774 tentura-31ve.4: forwardHelped Updates feed row.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/notification_settings/domain/entity/notification_settings.dart';
import 'package:tentura/features/updates/forward_helped_receipt_copy.dart';
import 'package:tentura/features/updates/ui/widget/forward_helped_see_path_action.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

const _viewerId = 'u-forwarder';
const _authorId = 'u-author';
const _midId = 'u-mid';
const _helperId = 'u-helper';
const _beaconId = 'b-774';
const _title = 'Need a van';

String _payload({
  bool done = false,
  bool blockedMiddle = false,
}) =>
    jsonEncode({
      'eventType': 'forwardHelped',
      'beaconId': _beaconId,
      'beaconTitle': _title,
      'authorId': _authorId,
      'helperId': _helperId,
      'done': done,
      'path': [
        {'userId': _authorId, 'displayName': 'Anna', 'anonymousCount': 0},
        if (blockedMiddle)
          {'anonymousCount': 1}
        else
          {'userId': _midId, 'displayName': 'Boris', 'anonymousCount': 0},
        {'userId': _viewerId, 'displayName': 'Kim', 'anonymousCount': 0},
        {'userId': _helperId, 'displayName': 'Vera', 'anonymousCount': 0},
      ],
    });

AttentionReceipt _receipt({
  String title = 'Your forward helped',
  int collapsedCount = 1,
  String payload = '',
}) => AttentionReceipt(
  id: 'r-fhelp',
  category: 'coordination',
  kind: 'commitmentEvent',
  priority: 'normal',
  title: title,
  body: '',
  actionUrl: '/#/view/$_beaconId',
  createdAt: DateTime.utc(2026, 11, 6),
  collapsedCount: collapsedCount,
  presentationKey: 'forward_helped',
  presentationPayloadJson: payload.isEmpty ? _payload() : payload,
  surface: AttentionSurface.activity,
  beaconId: _beaconId,
  beaconTitle: _title,
  targetEntityId: _helperId,
  destinationKind: 'beacon',
);

Future<void> _pumpTile(
  WidgetTester tester, {
  required AttentionReceipt receipt,
  required FakeUiEffectPort effects,
  Locale locale = const Locale('en'),
  VoidCallback? onDismiss,
}) async {
  final screen = ScreenCubit(effects);
  addTearDown(screen.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: BlocProvider<ScreenCubit>.value(
        value: screen,
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: UpdatesFeedTile(
              receipt: receipt,
              viewerUserId: _viewerId,
              onTap: () {},
              onMarkSeen: () {},
              onMarkUnseen: () {},
              activityRow: onDismiss != null,
              onDismiss: onDismiss,
              action: ForwardHelpedSeePathAction(receipt: receipt),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('accepted forwardHelped shows path, title, and author accepted', () {
    final en = L10nEn();
    final copy = forwardHelpedReceiptDisplayCopy(
      receiptTitle: 'Your forward helped',
      presentationKey: 'forward_helped',
      presentationPayloadJson: _payload(),
      l10n: en,
      collapsedCount: 1,
      viewerUserId: _viewerId,
    )!;
    expect(copy.headline, contains('Your forward helped'));
    expect(copy.body, contains('You'));
    expect(copy.body, contains('Boris'));
    expect(copy.body, contains('Vera'));
    expect(copy.body, contains(_title));
    expect(copy.body, contains('Anna'));
    expect(copy.body, contains('accepted'));
  });

  test('blocked hop renders as +1', () {
    final copy = forwardHelpedReceiptDisplayCopy(
      receiptTitle: 'Your forward helped',
      presentationKey: 'forward_helped',
      presentationPayloadJson: _payload(blockedMiddle: true),
      l10n: L10nEn(),
      collapsedCount: 1,
      viewerUserId: _viewerId,
    )!;
    expect(copy.body, contains('+1'));
    expect(copy.body, isNot(contains('Boris')));
  });

  test('done variant shows Done mark in headline', () {
    final copy = forwardHelpedReceiptDisplayCopy(
      receiptTitle: 'Your forward helped · Done ✓',
      presentationKey: 'forward_helped',
      presentationPayloadJson: _payload(done: true),
      l10n: L10nEn(),
      collapsedCount: 1,
      viewerUserId: _viewerId,
    )!;
    expect(copy.headline, contains('Done ✓'));
    expect(copy.body, contains(_title));
    expect(copy.body, contains('Vera'));
  });

  test('collapsedCount 2 uses plural headline', () {
    final copy = forwardHelpedReceiptDisplayCopy(
      receiptTitle: 'Your forward helped 2 people',
      presentationKey: 'forward_helped',
      presentationPayloadJson: _payload(),
      l10n: L10nEn(),
      collapsedCount: 2,
      viewerUserId: _viewerId,
    )!;
    expect(copy.headline, contains('2 people'));
  });

  testWidgets('See the path opens ForwardsGraphScreen for helper', (
    tester,
  ) async {
    final effects = FakeUiEffectPort();
    await _pumpTile(tester, receipt: _receipt(), effects: effects);
    await tester.tap(find.text('See the path ›'));
    await tester.pump();
    final push = effects.emitted.whereType<NavigatePush>().last;
    expect(
      push.path,
      '$kPathForwardsGraph/$_beaconId?'
      'committer=${Uri.encodeQueryComponent(_helperId)}'
      '&committerName=${Uri.encodeQueryComponent('Vera')}',
    );
  });

  testWidgets('× dismiss invokes onDismiss', (tester) async {
    var dismissed = false;
    await _pumpTile(
      tester,
      receipt: _receipt(),
      effects: FakeUiEffectPort(),
      onDismiss: () => dismissed = true,
    );
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  test('forward helped receipt category maps to settings toggle', () {
    expect(
      forwardHelpedNotificationSettingsCategory('coordination'),
      NotificationSettingsCategory.coordination,
    );
    expect(L10nEn().notificationCatCoordination, isNotEmpty);
  });

  testWidgets('RU locale at 375×667 renders without overflow', (tester) async {
    await usePhoneSurface(tester);
    await _pumpTile(
      tester,
      receipt: _receipt(),
      effects: FakeUiEffectPort(),
      locale: const Locale('ru'),
    );
    expect(find.textContaining('Ваша пересылка помогла'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
