@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show Request;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts.dart' show kContextJwtKey;
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart' show Env;

import '../../../support/disposable_pg_target.dart';
import '../../../support/post_bud_privacy_fixture.dart';
import '../../../support/session_database_di_harness.dart';

const _anna = PostBudPrivacyFixture.anna;
const _bob = PostBudPrivacyFixture.bob;
const _carol = PostBudPrivacyFixture.carol;
const _post = PostBudPrivacyFixture.post;
const _title = PostBudPrivacyFixture.title;
const _unknown = 'BbudUnknown00';
const _readableRequest = 'BbudReadable0';
const _budFact = 'The greenhouse frame weighs 80 kg.';
const _readableFact = 'Spare gloves are in the tool shed.';

const _activityDocument = r'''
query BeaconActivityEventList($beaconId: String!) {
  BeaconActivityEventList(beaconId: $beaconId) {
    id beaconId visibility type actorId targetUserId sourceMessageId
    coordinationItemId diffJson createdAt
  }
}
''';

const _myWorkDocument = r'''
query MyWorkLastActivityEvent($beaconIds: [String!]!) {
  myWorkLastActivityEvent(beaconIds: $beaconIds) {
    beaconId id type actorId actorTitle actorImageId createdAt diffJson
  }
}
''';

const _inboxDocument = r'''
query InboxRoomContextBatch($beaconIds: [String!]!) {
  InboxRoomContextBatch(beaconIds: $beaconIds) {
    beaconId
    isRoomMember
    currentLine
    lastRoomMeaningfulChange
    nextMoveText
    roomUnreadCount
    questionsUnreadCount
    unreadRoom
    lastSeenAt
    openBlockerTitle
    openBlockerCreatorId
    openBlockerTargetPersonId
    openBlockerResponsibleUserId
    openBlockerCreatedAt
    openBlockerCreatorDisplayName
    openBlockerCreatorImageId
    openBlockerCreatorHasPicture
    publicFactSnippet
    planSliceJson
    lastActivityAt
    lastMessageAt
    lastMessageText
    postRootExcerpt
    lastMessageAuthorId
    lastMessageAuthorName
    lastMessageKind
    parentBeaconId
    parentTitle
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PRIVATE_BUD_READS_TEST_DB',
    defaultNamePrefix: 'tentura_test_private_bud_reads',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late PostBudPrivacyFixture fixture;
  late GraphqlController controller;
  setUpAll(() async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // The fixture and the server graph open independent database executors.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases =
          previousWarningSetting;
    });
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    final db = target.databaseEnv;
    final env = Env(
      environment: Environment.dev,
      serverUri: Uri.parse('http://127.0.0.1:2080'),
      publicOrigin: 'http://127.0.0.1:2080',
      pgHost: db.pgHost,
      pgPort: db.pgPort,
      pgDatabase: db.pgDatabase,
      pgUsername: db.pgUsername,
      pgPassword: db.pgPassword,
      maxConnectionCount: 1,
      constellationDbMaxConcurrent: 1,
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      printEnv: false,
    );
    fixture = PostBudPrivacyFixture(session.writer, database, env);
    addTearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });
    await configureSessionDatabaseTestGraph(env);
    controller = GraphqlController(env);
  });

  setUp(() async {
    await fixture.reset();
    await fixture.seedPost();
  });

  Future<Map<String, Object?>> query(
    String viewer,
    String document,
    Map<String, Object?> variables,
  ) async {
    final response = await controller.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        context: {kContextJwtKey: JwtEntity(sub: viewer)},
        body: jsonEncode({'query': document, 'variables': variables}),
      ),
    );
    final json = await response.readAsString();
    expect(response.statusCode, 200, reason: json);
    return jsonDecode(json) as Map<String, Object?>;
  }

  Future<Map<String, Object?>> activity(String viewer, String id) =>
      query(viewer, _activityDocument, {'beaconId': id});

  Future<void> expectSameEmptyActivityAsUnknown(
    Map<String, Object?> unreadable,
  ) async {
    expect(_rows(unreadable, 'BeaconActivityEventList'), isEmpty);

    final unknown = await activity(_carol, _unknown);
    expect(_rows(unknown, 'BeaconActivityEventList'), isEmpty);
    expect(unreadable, unknown);
  }

  Future<List<Map<String, Object?>>> inbox(
    String viewer,
    List<String> ids,
  ) async => _rows(
    await query(viewer, _inboxDocument, {'beaconIds': ids}),
    'InboxRoomContextBatch',
  );

  Future<Map<String, Object?>> unknownInboxRow() async {
    final rows = await inbox(_carol, [_unknown]);
    expect(rows.map((row) => row['beaconId']), [_unknown]);
    return rows.single;
  }

  group('Activity for a private Request created from a Post', () {
    test(
      'unreadable Requests return the same empty activity as unknown IDs',
      () async {
        final bud = await fixture.bud(closePost: true);

        for (final viewer in [_bob, _anna]) {
          final events = _rows(
            await activity(viewer, bud),
            'BeaconActivityEventList',
          );
          expect(
            events,
            contains(
              _publicEvent(bud, BeaconActivityEventTypeBits.beaconPublished),
            ),
            reason: '$viewer can read the Request publication',
          );
        }
        final postEvents = _rows(
          await activity(_carol, _post),
          'BeaconActivityEventList',
        );
        expect(
          postEvents.where(
            (row) =>
                row['type'] ==
                BeaconActivityEventTypeBits.beaconLifecycleChanged,
          ),
          [
            _publicEvent(
              _post,
              BeaconActivityEventTypeBits.beaconLifecycleChanged,
            ),
          ],
        );

        await expectSameEmptyActivityAsUnknown(await activity(_carol, bud));
      },
    );

    test('the response to an uninvited Post member omits the title', () async {
      final bud = await fixture.bud();
      expect(jsonEncode(await activity(_anna, bud)), contains(_title));
      final unreadable = await activity(_carol, bud);
      expect(unreadable, isNot(contains('errors')));
      expect(jsonEncode(unreadable), isNot(contains(_title)));
      await expectSameEmptyActivityAsUnknown(unreadable);
    });

    test(
      'closing the Request keeps activity hidden from Post members',
      () async {
        final bud = await fixture.bud();
        await fixture.closeRequest(bud);

        final events = _rows(
          await activity(_anna, bud),
          'BeaconActivityEventList',
        );
        expect(
          events,
          contains(
            _publicEvent(
              bud,
              BeaconActivityEventTypeBits.beaconLifecycleChanged,
            ),
          ),
        );
        await expectSameEmptyActivityAsUnknown(await activity(_carol, bud));
      },
    );
  });

  group('My Work last activity for a private Request created from a Post', () {
    test('an uninvited Post member gets the unknown Request row', () async {
      final bud = await fixture.bud();
      Future<List<Map<String, Object?>>> myWork(String viewer, String id) async =>
          _rows(
            await query(viewer, _myWorkDocument, {
              'beaconIds': [id],
            }),
            'myWorkLastActivityEvent',
          );

      final annaRows = await myWork(_anna, bud);
      expect(annaRows.single['id'], isNotNull, reason: 'the author reads it');

      final unknown = await myWork(_carol, _unknown);
      final unreadable = await myWork(_carol, bud);
      expect(unreadable.single['id'], isNull);
      expect(unreadable.single['beaconId'], bud);
      expect(
        {...unreadable.single, 'beaconId': _unknown},
        unknown.single,
        reason: 'no field distinguishes it from an unknown Request',
      );
      expect(jsonEncode(unreadable), isNot(contains(_title)));
    });
  });

  group('Inbox room context for a private Request created from a Post', () {
    test('an uninvited Post member gets the unknown Request context', () async {
      final bud = await fixture.bud();
      await _seedPublicFact(fixture.writer, bud, _budFact);

      final invited = await inbox(_bob, [bud]);
      expect(invited, hasLength(1));
      expect(invited.single, containsPair('beaconId', bud));
      expect(invited.single, containsPair('publicFactSnippet', _budFact));

      final unknown = await unknownInboxRow();
      final unreadable = await inbox(_carol, [bud]);
      expect(unreadable, [
        {...unknown, 'beaconId': bud},
      ]);
      expect(unreadable.single, containsPair('publicFactSnippet', null));
    });

    test('a mixed batch keeps request order and readable facts', () async {
      final bud = await fixture.bud();
      await fixture.writer.execute(
        Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable, published_at)
VALUES (@id, @author, 'Tool shed supplies', '', 0, 0, false, now())
'''),
        parameters: {'id': _readableRequest, 'author': _anna},
      );
      await fixture.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@id, @author, @viewer)
'''),
        parameters: {'id': _readableRequest, 'author': _anna, 'viewer': _carol},
      );
      await _seedPublicFact(fixture.writer, bud, _budFact);
      await _seedPublicFact(fixture.writer, _readableRequest, _readableFact);
      expect(await fixture.canRead(_readableRequest, _carol), isTrue);

      final batch = await inbox(_carol, [bud, _readableRequest]);
      final reversed = await inbox(_carol, [_readableRequest, bud]);
      expect(batch.map((row) => row['beaconId']), [bud, _readableRequest]);
      expect(reversed, batch.reversed);
      expect(batch.last, containsPair('isRoomMember', false));
      expect(batch.last, containsPair('publicFactSnippet', _readableFact));
      final unknown = await unknownInboxRow();
      expect(batch.first, {...unknown, 'beaconId': bud});
      expect(batch.first, containsPair('publicFactSnippet', null));
    });
  });
}

List<Map<String, Object?>> _rows(Map<String, Object?> body, String field) {
  expect(body, isNot(contains('errors')), reason: jsonEncode(body));
  final data = body['data']! as Map<String, Object?>;
  return (data[field]! as List<Object?>).cast<Map<String, Object?>>();
}

Matcher _publicEvent(String beaconId, int type) => allOf(
  containsPair('beaconId', beaconId),
  containsPair('visibility', BeaconActivityEventVisibilityBits.public),
  containsPair('type', type),
);

Future<void> _seedPublicFact(
  Connection writer,
  String beaconId,
  String text,
) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_fact_card (beacon_id, fact_text, visibility, pinned_by)
VALUES (@id, @text, @visibility, @author)
'''),
    parameters: {
      'id': beaconId,
      'text': text,
      'visibility': BeaconFactCardVisibilityBits.public,
      'author': _anna,
    },
  );
}
