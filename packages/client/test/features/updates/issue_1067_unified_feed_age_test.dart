// #1067 — one card-relative age on Activity and History feed rows; history
// naming. Real path: wire invite-accepted receipts → AttentionRepository.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/util/relative_time.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

final _now = DateTime.utc(2026, 11, 7, 12);

AttentionReceipt _inviteAccepted({
  required String id,
  required Duration age,
}) {
  final createdAt = _now.subtract(age);
  return AttentionReceipt(
    id: id,
    category: 'connections',
    kind: 'inviteAccepted',
    priority: 'normal',
    title: 'New connection',
    body: 'Body',
    actionUrl: '/#/',
    createdAt: createdAt,
    collapsedCount: 1,
    presentationPayloadJson: '{"inviteOrigin":"new_account"}',
    surface: AttentionSurface.activity,
    presentationKey: 'invite_accepted',
    actorUserId: 'invitee-$id',
    targetEntityId: 'invitee-$id',
  );
}

Map<String, dynamic> _wireInvite(int i, String iso) => {
  '__typename': 'v2_AttentionReceipt',
  'id': 'Ninvite00000$i',
  'category': 'connections',
  'kind': 'inviteAccepted',
  'priority': 'low',
  'title': 'Connection $i',
  'body': 'Body',
  'actionUrl': '/#/profile/invitee-$i',
  'createdAt': iso,
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': null,
  'coordinationItemId': null,
  'actorUserId': 'Uinvitee0000$i',
  'sourceEventKey': 'invite:$i',
  'destinationKind': 'user',
  'targetEntityId': 'Uinvitee0000$i',
  'presentationKey': 'invite_accepted',
  'presentationPayloadJson': '{"inviteOrigin":"new_account"}',
  'inAppPreferenceClass': null,
  'requiresAction': false,
  'attentionThreadKey': null,
  'settlementKind': null,
  'settledAt': null,
  'clearedAt': null,
  'clearReason': null,
  'surface': 'activity',
  'itemKind': 'receipt',
  'forwardOutcome': null,
  'forwardCount': null,
  'digestCount': null,
  'eventTotal': null,
  'eventUnseenCount': null,
  'provenanceJson': null,
  'beaconAuthorId': null,
  'beaconAuthorName': null,
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': null,
  'beaconTitle': null,
  'beaconKind': null,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': <Object?>[],
};

Future<void> _pumpTile(
  WidgetTester tester, {
  required AttentionReceipt receipt,
  required bool activityRow,
  required Locale locale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: UpdatesFeedTile(
            receipt: receipt,
            onTap: () {},
            onMarkSeen: () {},
            onMarkUnseen: () {},
            activityRow: activityRow,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    RelativeTimestampTicker.debugClock = () => _now.toLocal();
  });
  tearDown(() => RelativeTimestampTicker.debugClock = null);

  test('RU copy names the menu and the screen separately', () {
    final ru = lookupL10n(const Locale('ru'));
    expect(ru.notificationHistoryTitle, 'История уведомлений');
    expect(ru.notificationHistoryScreenTitle, 'История');
  });

  test('wire invite-accepted rows map with v2 shapes', () async {
    final sent = <WireSent>[];
    final items = [
      _wireInvite(1, _now.subtract(const Duration(hours: 1)).toIso8601String()),
      _wireInvite(2, _now.subtract(const Duration(hours: 2)).toIso8601String()),
    ];
    await withRemoteWire(
      {
        'AttentionFeed': {
          '__typename': 'query_root',
          'attentionFeed': {
            '__typename': 'v2_AttentionFeed',
            'summary': {
              '__typename': 'v2_AttentionSummary',
              'unreadTotal': 2,
              'needsYouTotal': 0,
            },
            'page': {
              '__typename': 'v2_AttentionPage',
              'nextCursor': null,
              'items': items,
            },
          },
        },
      },
      sent,
      (remote) async {
        final page = await AttentionRepository(remote).fetch(
          view: AttentionView.all,
          surface: AttentionSurface.activity,
        );
        expect(page.page.items, hasLength(2));
        expect(
          page.page.items.map((r) => r.presentationKey),
          everyElement('invite_accepted'),
        );
      },
    );
  });

  testWidgets('375×667 RU: Activity and History rows show the same ages', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final ru = L10nRu();
    final receipt = _inviteAccepted(id: 'a', age: const Duration(hours: 1));

    final ageText = ru.relativeTimeCompactHours(1);

    await _pumpTile(
      tester,
      receipt: receipt,
      activityRow: true,
      locale: const Locale('ru'),
    );
    expect(find.text(ageText), findsOneWidget);

    await _pumpTile(
      tester,
      receipt: receipt,
      activityRow: false,
      locale: const Locale('ru'),
    );
    expect(find.text(ageText), findsOneWidget);
    expect(find.textContaining(' назад'), findsNothing);
    expect(
      cardRelativeAgeSpoken(
        when: receipt.createdAt,
        now: _now.toLocal(),
        l10n: ru,
      ),
      ru.relativeTimeSpokenHours(1),
    );
  });

  testWidgets('375×667 RU: three invite receipts read 1 ч, 2 ч, 3 ч', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final ru = L10nRu();
    final receipts = [
      _inviteAccepted(id: '1', age: const Duration(hours: 1)),
      _inviteAccepted(id: '2', age: const Duration(hours: 2)),
      _inviteAccepted(id: '3', age: const Duration(hours: 3)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Scaffold(
            body: ListView(
              children: [
                for (final receipt in receipts)
                  UpdatesFeedTile(
                    receipt: receipt,
                    onTap: () {},
                    onMarkSeen: () {},
                    onMarkUnseen: () {},
                    activityRow: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(ru.relativeTimeCompactHours(1)), findsOneWidget);
    expect(find.text(ru.relativeTimeCompactHours(2)), findsOneWidget);
    expect(find.text(ru.relativeTimeCompactHours(3)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
