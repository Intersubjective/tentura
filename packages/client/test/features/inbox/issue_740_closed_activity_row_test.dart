// #740: after a Request closes, a declined invitee's Activity row was the
// pinned card again — «something for you», Offer help, Forward — because
// the card treats every pinned forward as a decision and never reads the
// Request's status. The status is already on the beacon, and a status
// receipt the feed already returns (`toStatus`).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/request_attention_predicate.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card.dart';
import 'package:tentura/features/inbox/ui/widget/request_attention_card_mapper.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';
import '../../support/remote_wire_harness.dart';

const _title = 'Book swap Sunday';

Beacon _beacon({
  BeaconStatus status = BeaconStatus.closed,
  DateTime? statusChangedAt,
}) => Beacon(
  id: 'b1',
  title: _title,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10, 24, 17),
  status: status,
  statusChangedAt: statusChangedAt,
  author: const Profile(id: 'alice', displayName: 'Alice'),
  viewerCanForward: status.allowsForward,
);

AttentionReceipt _event({
  required String id,
  required String eventType,
  required String presentationKey,
  required DateTime createdAt,
  bool personal = false,
  String? toStatus,
  String? outcome,
  String actorUserId = 'alice',
}) => AttentionReceipt(
  id: id,
  category: 'requestProgress',
  kind: 'roomActivityLowPriority',
  priority: 'normal',
  title: _title,
  body: '',
  actionUrl: '/#/',
  createdAt: createdAt,
  collapsedCount: 1,
  presentationKey: presentationKey,
  presentationPayloadJson: [
    '{"eventType":"$eventType","personal":$personal',
    if (toStatus != null) ',"toStatus":"$toStatus"',
    if (outcome != null) ',"outcome":"$outcome"',
    '}',
  ].join(),
  surface: AttentionSurface.activity,
  beaconId: 'b1',
  actorUserId: actorUserId,
);

Widget _card({
  required Beacon beacon,
  List<AttentionReceipt> events = const [],
  bool pendingForward = true,
}) => RequestAttentionCard(
  beacon: beacon,
  variant: RequestAttentionCardVariant.pinned,
  facts: RequestAttentionFacts(
    requestId: beacon.id,
    pendingForward: pendingForward,
  ),
  eventsPreview: events,
  onOpenBeacon: () {},
  onOpenTimeline: () {},
  onOfferHelp: () {},
  onForward: () {},
  onFollow: () {},
);

Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('ru'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: Scaffold(body: child)),
);

Future<void> _pump(WidgetTester tester, Widget card) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(_app(card));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a closed Request row offers no help or forward and no «something for you»',
    (tester) async {
      await _pump(
        tester,
        _card(
          beacon: _beacon(),
          events: [
            _event(
              id: 'invite',
              eventType: 'authorInviteReceived',
              presentationKey: 'author_invite_received',
              createdAt: DateTime.utc(2026, 10, 24, 16),
              personal: true,
            ),
            _event(
              id: 'closed',
              eventType: 'requestStatusChanged',
              presentationKey: 'request_status_changed',
              createdAt: DateTime.utc(2026, 10, 24, 17),
              toStatus: 'closed',
            ),
          ],
        ),
      );

      expect(find.text('Предложить помощь'), findsNothing);
      expect(find.text('Переслать'), findsNothing);
      expect(
        find.byKey(RequestAttentionCard.forYouIndicatorKey),
        findsNothing,
      );
      expect(find.text('Статус: Закрыт'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a closed row still marks a message addressed to the viewer',
    (tester) async {
      await _pump(
        tester,
        _card(
          beacon: _beacon(),
          pendingForward: false,
          events: [
            _event(
              id: 'msg',
              eventType: 'roomMessagePosted',
              presentationKey: 'room_message_posted',
              createdAt: DateTime.utc(2026, 10, 24, 17, 5),
              personal: true,
            ),
          ],
        ),
      );

      expect(
        find.byKey(RequestAttentionCard.forYouIndicatorKey),
        findsOneWidget,
      );
      expect(find.text('Предложить помощь'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets("a closed row marks the viewer's own result", (tester) async {
    await _pump(
      tester,
      _card(
        beacon: _beacon(),
        pendingForward: false,
        events: [
          _event(
            id: 'result',
            eventType: 'closureFinalized',
            presentationKey: 'closure_finalized',
            createdAt: DateTime.utc(2026, 10, 24, 17),
            outcome: 'helped',
          ),
        ],
      ),
    );

    expect(find.byKey(RequestAttentionCard.forYouIndicatorKey), findsOneWidget);
    expect(find.text('Предложить помощь'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reopened Request offers help again', (tester) async {
    await _pump(
      tester,
      _card(
        beacon: _beacon(
          status: BeaconStatus.open,
          statusChangedAt: DateTime.utc(2026, 10, 25),
        ),
        events: [
          _event(
            id: 'closed',
            eventType: 'requestStatusChanged',
            presentationKey: 'request_status_changed',
            createdAt: DateTime.utc(2026, 10, 24, 17),
            toStatus: 'closed',
          ),
        ],
      ),
    );

    expect(find.text('Предложить помощь'), findsOneWidget);
    expect(find.text('Переслать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'activityOffers wire maps a close, and the card drops the call to action',
    (tester) async {
      final mapped = <AttentionReceipt>[];
      await withRemoteWire(
        {
          'ActivityOffersV2': {
            '__typename': 'query_root',
            'activityOffers': {
              '__typename': 'ActivityOfferPage',
              'totalCount': 1,
              'nextCursor': null,
              'items': [
                {
                  '__typename': 'ActivityOfferSortRow',
                  'beaconId': 'b1',
                  'listPositionAt': '2026-10-24T17:00:00.000Z',
                  'effectiveActivityAt': '2026-10-24T17:00:00.000Z',
                  'latestForwardAt': '2026-10-24T16:00:00.000Z',
                  'unseen': true,
                  'eventTotal': 2,
                  'eventUnseenCount': 1,
                  'inviteId': null,
                  'declinedInvite': true,
                  'eventsPreview': [
                    _wire(
                      id: 'invite',
                      eventType: 'authorInviteReceived',
                      presentationKey: 'author_invite_received',
                      createdAt: '2026-10-24T16:00:00.000Z',
                      personal: true,
                    ),
                    _wire(
                      id: 'closed',
                      eventType: 'requestStatusChanged',
                      presentationKey: 'request_status_changed',
                      createdAt: '2026-10-24T17:00:00.000Z',
                      toStatus: 'closed',
                    ),
                  ],
                },
              ],
            },
          },
        },
        <WireSent>[],
        (remote) async {
          final page = await AttentionRepository(remote).activityOffers();
          mapped.addAll(page.items.single.eventsPreview);
        },
      );

      final close = mapped.singleWhere((e) => e.id == 'closed');
      final model = requestCardFromReceipt(
        close.copyWith(
          itemKind: AttentionItemKind.requestActivity,
          beaconId: 'b1',
          title: _title,
          eventsPreview: mapped,
          allowsForward: false,
        ),
      )!;

      expect(model.beacon.status, BeaconStatus.closed);

      await _pump(
        tester,
        RequestAttentionCard(
          beacon: model.beacon,
          variant: RequestAttentionCardVariant.pinned,
          facts: const RequestAttentionFacts(
            requestId: 'b1',
            pendingForward: true,
          ),
          eventsPreview: model.eventsPreview,
          onOpenBeacon: () {},
          onOpenTimeline: () {},
          onOfferHelp: () {},
          onForward: () {},
        ),
      );
      expect(find.text('Предложить помощь'), findsNothing);
      expect(find.text('Переслать'), findsNothing);
      expect(
        find.byKey(RequestAttentionCard.forYouIndicatorKey),
        findsNothing,
      );
      expect(find.text('Статус: Закрыт'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, dynamic> _wire({
  required String id,
  required String eventType,
  required String presentationKey,
  required String createdAt,
  bool personal = false,
  String? toStatus,
}) => {
  '__typename': 'AttentionReceipt',
  'id': id,
  'category': 'requestProgress',
  'kind': 'roomActivityLowPriority',
  'priority': 'normal',
  'title': _title,
  'body': '',
  'actionUrl': '/#/',
  'createdAt': createdAt,
  'seenAt': null,
  'collapsedCount': 1,
  'beaconId': 'b1',
  'coordinationItemId': null,
  'actorUserId': 'alice',
  'sourceEventKey': null,
  'destinationKind': 'beacon',
  'targetEntityId': 'b1',
  'presentationKey': presentationKey,
  'presentationPayloadJson': [
    '{"eventType":"$eventType","personal":$personal',
    if (toStatus != null) ',"toStatus":"$toStatus"',
    '}',
  ].join(),
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
  'beaconAuthorId': 'alice',
  'beaconAuthorName': 'Alice',
  'beaconAuthorImageId': null,
  'beaconImageId': null,
  'beaconEndAt': null,
  'allowsForward': false,
  'beaconTitle': _title,
  'beaconKind': 0,
  'postRootExcerpt': null,
  'postRootImageId': null,
  'eventsPreview': <Object?>[],
};
