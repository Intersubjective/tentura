@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/production_receipt_transport.dart';

const _anna = Profile(id: 'Ubaton0000001', displayName: 'Anna');
const _carol = Profile(id: 'Ubaton0000002', displayName: 'Carol');
const _boris = Profile(id: 'Ubaton0000003', displayName: 'Boris');
const _pair = 'Carol and Boris';
const _taken = 'Carol and Boris took it.';

Future<List<RoomMessage>> _readRoom(
  ProductionReceiptTransport transport, {
  String? pick,
}) async {
  final response = await transport.graphql(
    _anna.id,
    {'pick': ?pick},
    path: '/room',
  );
  final body = jsonDecode(response.body) as Map;
  expect(body['errors'], isNull);
  return [
    for (final row in (body['messages'] as List).cast<Map<String, dynamic>>())
      RoomMessage(
        id: row['id'] as String,
        beaconId: row['beaconId'] as String,
        authorId: row['authorId'] as String,
        body: row['body'] as String,
        createdAt: DateTime.parse(row['createdAt'] as String),
        semanticMarker: row['semanticMarker'] as int?,
        systemPayloadJson: row['systemPayloadJson'] as String?,
        baton: RoomBatonData.tryParse(row['batonDataJson'] as String?),
      ),
  ];
}

Future<void> _expectPairReceipt(
  ProductionReceiptTransport transport, {
  required Profile viewer,
  required Profile partner,
  required RoomMessage ask,
}) async {
  final response = await transport.graphql(viewer.id, {
    'query': r'''
      query PairOutcome($beaconId: String!) {
        attentionRequestHistory(beaconId: $beaconId) {
          items { presentationKey presentationPayloadJson targetEntityId }
        }
      }
    ''',
    'variables': {'beaconId': ask.beaconId},
  });
  final body = jsonDecode(response.body) as Map;
  expect(body['errors'], isNull);
  final history = (body['data'] as Map)['attentionRequestHistory'] as Map;
  final receipts = (history['items'] as List).cast<Map<String, dynamic>>();
  final outcomes = receipts.where(
    (receipt) => receipt['presentationKey'] == 'baton_taken',
  );
  expect(outcomes, hasLength(1), reason: '${viewer.displayName} was picked');
  final outcome = outcomes.single;
  expect(outcome['targetEntityId'], ask.id);
  final payload =
      jsonDecode(outcome['presentationPayloadJson'] as String) as Map;
  expect(
    payload['withUserId'],
    partner.id,
    reason: 'The receipt names the other taker',
  );
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(child: Scaffold(body: child)),
);

RoomMessageTile _systemLine(RoomMessage marker, RoomMessage intervening) =>
    RoomMessageTile(
      message: marker,
      previousMessage: intervening,
      myProfile: _anna,
      participants: [
        for (final person in [_boris, _carol])
          BeaconParticipant(
            id: 'participant-${person.id}',
            beaconId: marker.beaconId,
            userId: person.id,
            role: BeaconParticipantRoleBits.helper,
            status: 0,
            roomAccess: RoomAccessBits.admitted,
            createdAt: DateTime.utc(2026, 11, 19),
            updatedAt: DateTime.utc(2026, 11, 19),
            userTitle: person.displayName,
          ),
      ],
    );

void main() {
  late ProductionReceiptTransport transport;
  setUpAll(() async {
    transport = await ProductionReceiptTransport.start(
      serverFixture: 'test/support/baton_receipt_transport.dart',
    );
  });
  tearDownAll(() => transport.close());

  testWidgets(
    'The pair keeps its answer-row name order after the author chooses it',
    (
      tester,
    ) async {
      final collecting = (await tester.runAsync(() => _readRoom(transport)))!;
      final answer = collecting.singleWhere((message) => message.baton != null);
      final picks = <String?>[];
      await tester.pumpWidget(
        _app(
          RoomBatonCard(
            baton: answer.baton!,
            onSelect: picks.add,
          ),
        ),
      );
      expect(find.text(_pair), findsOneWidget);
      expect(find.text('Boris and Carol'), findsNothing);

      await tester.tap(find.text('Choose now'));
      await tester.pumpAndSettle();
      final choice = find.widgetWithText(ListTile, _pair);
      expect(choice, findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Boris and Carol'), findsNothing);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(picks, [_carol.id]);

      final resolved = (await tester.runAsync(
        () => _readRoom(transport, pick: picks.single),
      ))!;
      final taken = resolved.singleWhere((message) => message.id == answer.id);
      final result = taken.baton! as RoomBatonAuthorData;
      expect(result.status, RoomBatonStatus.taken);
      expect({result.taker?.id, result.coTaker?.id}, {_carol.id, _boris.id});
      await tester.runAsync(() async {
        await _expectPairReceipt(
          transport,
          viewer: _carol,
          partner: _boris,
          ask: answer,
        );
        await _expectPairReceipt(
          transport,
          viewer: _boris,
          partner: _carol,
          ask: answer,
        );
      });

      final systemLine = resolved.singleWhere(
        (message) =>
            message.semanticMarker == BeaconRoomSemanticMarker.batonTaken,
      );
      final intervening = resolved.singleWhere(
        (message) => message.body == 'Ready to help',
      );
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              RoomBatonCard(baton: result),
              _systemLine(systemLine, intervening),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final actual = {
        'taken baton card': [
          for (final text
              in find
                  .descendant(
                    of: find.byType(RoomBatonCard),
                    matching: find.byType(Text),
                  )
                  .evaluate())
            (text.widget as Text).data,
        ],
        'room system line': [
          for (final text
              in find
                  .descendant(
                    of: find.byType(RoomMessageTile),
                    matching: find.byType(Text),
                  )
                  .evaluate())
            (text.widget as Text).data,
        ],
      };
      expect(actual, {
        for (final place in actual.keys)
          place: allOf(
            contains(_taken),
            isNot(anyElement(contains('Boris and Carol'))),
          ),
      });
    },
  );
}
