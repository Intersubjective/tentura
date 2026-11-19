@Tags(['pg'])
library;

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/post_bud_privacy_fixture.dart';

const _bob = PostBudPrivacyFixture.bob;
const _carol = PostBudPrivacyFixture.carol;
const _post = PostBudPrivacyFixture.post;
const _title = PostBudPrivacyFixture.title;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_ROOM_PRIVACY_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_room_privacy',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late PostBudPrivacyFixture fixture;
  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    fixture = PostBudPrivacyFixture(
      session.writer,
      database,
      target.databaseEnv,
    );
  });

  setUp(() async {
    await fixture.reset();
    await fixture.seedPost();
  });

  test('only invited Post readers see the Request lifecycle notice', () async {
    final child = await fixture.bud();
    await fixture.closeRequest(child);
    expect(
      (await fixture.beacons.getBeaconById(beaconId: child)).status,
      BeaconStatus.closed,
    );
    expect(await fixture.canRead(child, _bob), isTrue);
    expect(await fixture.canRead(child, _carol), isFalse);

    final bobRoom = await fixture.room.listMessages(
      beaconId: _post,
      userId: _bob,
    );
    final carolRoom = await fixture.room.listMessages(
      beaconId: _post,
      userId: _carol,
    );
    expect(
      carolRoom.map((message) => message['id']),
      contains(PostBudPrivacyFixture.postRoot),
    );
    final bobLifecycle = bobRoom.where(
      (message) =>
          message['systemMessageKind'] ==
          BeaconRoomSystemMessageKind.hierarchyLifecycle,
    );
    expect(bobLifecycle, hasLength(1));
    expect(jsonEncode(bobLifecycle.single), contains(_title));
    expect(jsonEncode(bobLifecycle.single), contains('A child request'));

    final forbidden = await _unauthorizedDispatch(fixture, child);
    final carolTargets = await _hierarchyTargetsVisibleInRoom(
      fixture,
      child,
      carolRoom,
    );
    final carolWire = jsonEncode(carolRoom);
    expect(
      {
        ...forbidden,
        'hierarchy delivery targets visible to Carol': carolTargets,
        'room mentions child ID': carolWire.contains(child),
        'room mentions child title': carolWire.contains(_title),
        'room contains a Request creation or lifecycle notice': carolRoom.any(
          (message) => const [
            BeaconRoomSystemMessageKind.childCreated,
            BeaconRoomSystemMessageKind.hierarchyLifecycle,
          ].contains(message['systemMessageKind']),
        ),
        'room describes a child lifecycle change': carolWire.contains(
          'A child request',
        ),
      },
      {
        'attention': isEmpty,
        'channel deliveries': isEmpty,
        'notification receipts': isEmpty,
        'hierarchy delivery targets visible to Carol': isEmpty,
        'room mentions child ID': false,
        'room mentions child title': false,
        'room contains a Request creation or lifecycle notice': false,
        'room describes a child lifecycle change': false,
      },
    );
  });

  test(
    'closing a Post names the continuation only for invited readers',
    () async {
      final child = await fixture.bud(closePost: true);
      expect(
        (await fixture.beacons.getBeaconById(beaconId: _post)).status,
        BeaconStatus.closed,
      );
      Future<List<Map<String, Object?>>> roomFor(String viewer) async {
        final room = await fixture.room.listMessages(
          beaconId: _post,
          userId: viewer,
        );
        expect(
          room.map((message) => message['id']),
          contains(PostBudPrivacyFixture.postRoot),
        );
        return room;
      }

      Map<String, Object?> closingNotice(
        List<Map<String, Object?>> room,
        String viewer,
      ) {
        final notices = room.where(
          (message) =>
              message['systemMessageKind'] ==
              BeaconRoomSystemMessageKind.postClosed,
        );
        expect(notices, hasLength(1), reason: '$viewer sees one Post closure');
        return notices.single;
      }

      final bobNotice = closingNotice(await roomFor(_bob), 'Bob');
      final carolRoom = await roomFor(_carol);
      final carolNotice = closingNotice(carolRoom, 'Carol');
      final carolTargets = await _hierarchyTargetsVisibleInRoom(
        fixture,
        child,
        carolRoom,
      );
      final carolWire = jsonEncode(carolRoom);
      final bobPayload = jsonDecode(bobNotice['systemPayloadJson']! as String);
      expect(
        bobPayload,
        allOf(
          containsPair('childBeaconId', child),
          containsPair('title', _title),
        ),
      );
      expect(
        {
          'Carol closure notice': jsonEncode(carolNotice),
          ...await _unauthorizedDispatch(fixture, child),
          'hierarchy delivery targets visible to Carol': carolTargets,
          'Carol sees the Request ID': carolWire.contains(child),
          'Carol sees the Request title': carolWire.contains(_title),
          'Carol sees a Request creation notice': carolRoom.any(
            (message) =>
                message['systemMessageKind'] ==
                BeaconRoomSystemMessageKind.childCreated,
          ),
        },
        {
          'Carol closure notice': allOf(
            isNot(contains(child)),
            isNot(contains(_title)),
          ),
          'attention': isEmpty,
          'channel deliveries': isEmpty,
          'notification receipts': isEmpty,
          'hierarchy delivery targets visible to Carol': isEmpty,
          'Carol sees the Request ID': false,
          'Carol sees the Request title': false,
          'Carol sees a Request creation notice': false,
        },
      );
    },
  );
}

/// Delivery targets are rooms. Follow a target's emitted notice into the
/// viewer's room response to tell whether this target actually reached them.
Future<List<Map<String, Object?>>> _hierarchyTargetsVisibleInRoom(
  PostBudPrivacyFixture fixture,
  String child,
  List<Map<String, Object?>> room,
) async {
  final targets = await fixture.writer.execute(
    Sql.named('''
SELECT d.event_id, e.source_beacon_id, d.target_beacon_id, d.notice_message_id
FROM public.beacon_hierarchy_deliveries d
JOIN public.beacon_hierarchy_events e ON e.id = d.event_id
WHERE (e.source_beacon_id = @child AND d.target_beacon_id = @post)
   OR (e.source_beacon_id = @post AND d.target_beacon_id = @child)
'''),
    parameters: {'child': child, 'post': _post},
  );
  final visibleIds = {for (final message in room) message['id']};
  return [
    for (final target in targets)
      if (visibleIds.contains(target[3])) target.toColumnMap(),
  ];
}

/// Check all unreadable recipients of the materialized attention and channel
/// records. A Post-scoped record can refer to the child in its payload too.
Future<Map<String, Object?>> _unauthorizedDispatch(
  PostBudPrivacyFixture fixture,
  String child,
) async {
  Future<List<String>> recipients(String sql) async => [
    for (final row in await fixture.writer.execute(
      Sql.named(sql),
      parameters: {'child': child, 'title': _title},
    ))
      row.single! as String,
  ];

  final outbox = NotificationOutboxRepository(fixture.database);
  final bobReceipts = await outbox.pendingForAccount(_bob);
  expect(bobReceipts.map((item) => item.beaconId), contains(child));

  return {
    'attention': await recipients('''
SELECT r.account_id
FROM public.attention_occurrence_recipient r
JOIN public.attention_occurrence o ON o.id = r.occurrence_id
WHERE NOT public.beacon_can_read_content(@child, r.account_id)
  AND (strpos(o.immutable_payload::text || r.role_facts::text, @child) > 0
    OR strpos(o.immutable_payload::text || r.role_facts::text, @title) > 0)
'''),
    'channel deliveries': await recipients('''
SELECT d.account_id FROM public.attention_channel_delivery d
WHERE NOT public.beacon_can_read_content(@child, d.account_id)
  AND (strpos(d.payload::text, @child) > 0 OR strpos(d.payload::text, @title) > 0)
'''),
    'notification receipts': await recipients('''
SELECT n.account_id FROM public.notification_outbox n
WHERE NOT public.beacon_can_read_content(@child, n.account_id)
  AND (n.beacon_id = @child
    OR strpos(to_jsonb(n)::text, @child) > 0
    OR strpos(to_jsonb(n)::text, @title) > 0)
'''),
  };
}
