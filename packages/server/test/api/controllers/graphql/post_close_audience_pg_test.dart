@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:graphql_server2/graphql_server2.dart' show GraphQL;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_hierarchy_consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/post_bud_privacy_fixture.dart';
import '../../../support/session_database_di_harness.dart';

const _anna = PostBudPrivacyFixture.anna;
const _bob = PostBudPrivacyFixture.bob;
const _carol = PostBudPrivacyFixture.carol;
const _post = PostBudPrivacyFixture.post;
const _title = PostBudPrivacyFixture.title;
const _root = PostBudPrivacyFixture.postRoot;
const _plainPost = 'BbudprivacyQ0';
const _plainRoot = 'RbudprivacyQ';

const _activity = r'''
query BeaconActivityEventList($beaconId: String!) {
  BeaconActivityEventList(beaconId: $beaconId) {
    id beaconId visibility type actorId targetUserId sourceMessageId
    coordinationItemId diffJson createdAt
  }
}
''';

const _summary = r'''
query PostSummary($id: String!) {
  postSummary(id: $id) { id status expiresAt }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_CLOSE_AUDIENCE_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_close_audience',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late PostBudPrivacyFixture fixture;
  late GraphQL schema;
  setUpAll(() async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    // The fixture and generated DI graph use independent database executors.
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
    schema = graphqlSchema;
  });

  setUp(() async {
    await fixture.reset();
    await fixture.seedPost();
    await fixture.writer.execute('''
UPDATE public.beacon SET expires_at = now() + interval '1 day'
WHERE id = '$_post'
''');
  });

  Future<Map<String, Object?>> query(
    String viewer,
    String document,
    Map<String, Object?> variables,
  ) async =>
      await schema.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {kGlobalInputQueryJwt: JwtEntity(sub: viewer)},
          )
          as Map<String, Object?>;

  test(
    'Post members see a plain close unless invited to the continuation',
    () async {
      await _seedPlainPost(fixture.writer);
      final child = await fixture.bud(closePost: true);
      final close = await query(
        _anna,
        r'''
mutation Close($id: String!) { postClose(id: $id) }
''',
        {'id': _plainPost},
      );
      expect(close['postClose'], isTrue);

      final budActivity = await query(_carol, _activity, {'beaconId': _post});
      final plainActivity = await query(_carol, _activity, {
        'beaconId': _plainPost,
      });
      final budEvent = _onlyLifecycleEvent(budActivity, _post);
      final plainEvent = _onlyLifecycleEvent(plainActivity, _plainPost);

      final carolRoom = await fixture.room.listMessages(
        beaconId: _post,
        userId: _carol,
      );
      final plainRoom = await fixture.room.listMessages(
        beaconId: _plainPost,
        userId: _carol,
      );
      final bobRoom = await fixture.room.listMessages(
        beaconId: _post,
        userId: _bob,
      );

      expect(await fixture.canRead(child, _bob), isTrue);
      expect(await fixture.canRead(child, _carol), isFalse);
      expect(_closeNoticePayload(bobRoom, _root), {
        'reason': 'budded',
        'childBeaconId': child,
        'title': _title,
      });
      final plainNotice = _closeNoticePayload(plainRoom, _plainRoot);
      expect(plainNotice, {'reason': 'closedByAuthor'});
      expect(_closeNoticePayload(carolRoom, _root), plainNotice);
      for (final response in [carolRoom, budActivity]) {
        expect(
          jsonEncode(response),
          allOf(isNot(contains(child)), isNot(contains(_title))),
        );
      }

      final plainClosure = _comparableEvent(plainEvent);
      expect(plainClosure['actorId'], _anna);
      expect(
        plainClosure['diffJson'],
        allOf(
          containsPair('reason', 'postClosedByAuthor'),
          containsPair('fromStatus', 0),
          containsPair('toStatus', 6),
        ),
      );
      expect(_comparableEvent(budEvent), plainClosure);
    },
  );

  test('a Post member sees the closed Post end when it closes', () async {
    Future<DateTime> databaseTime() async =>
        (await fixture.writer.execute(
              'SELECT clock_timestamp()',
            )).single.single!
            as DateTime;

    Future<Map<String, Object?>> readPost(int status) async {
      final result = await query(_carol, _summary, {'id': _post});
      final post = result['postSummary'];
      if (post is! Map<String, Object?>) {
        fail('Carol should receive the Post summary, got $result');
      }
      expect(post['id'], _post);
      expect(post['status'], status);
      return post;
    }

    final openPost = await readPost(0);
    final scheduledEnd = DateTime.parse(openPost['expiresAt']! as String);
    expect(scheduledEnd.isAfter(await databaseTime()), isTrue);

    await fixture.bud(closePost: true);
    final closeCompletedAt = await databaseTime();

    final closedPost = await readPost(6);
    final actualEnd = DateTime.parse(closedPost['expiresAt']! as String);
    expect(
      actualEnd.microsecondsSinceEpoch,
      lessThanOrEqualTo(closeCompletedAt.microsecondsSinceEpoch),
      reason:
          'Carol sees expiry $actualEnd for the Post closed at '
          '$closeCompletedAt',
    );
  });
}

Map<String, Object?> _onlyLifecycleEvent(
  Map<String, Object?> response,
  String post,
) {
  final events = (response['BeaconActivityEventList']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .where(
        (row) =>
            row['type'] == BeaconActivityEventTypeBits.beaconLifecycleChanged,
      );
  expect(events, hasLength(1));
  expect(events.single['beaconId'], post);
  return events.single;
}

Map<String, Object?> _comparableEvent(Map<String, Object?> event) =>
    Map<String, Object?>.of(event)
      ..remove('id')
      ..remove('beaconId')
      ..remove('createdAt')
      ..['diffJson'] = jsonDecode(event['diffJson']! as String);

Object? _closeNoticePayload(List<Map<String, Object?>> room, String root) {
  expect(room.map((message) => message['id']), contains(root));
  final notices = room.where(
    (message) =>
        message['systemMessageKind'] == BeaconRoomSystemMessageKind.postClosed,
  );
  expect(notices, hasLength(1));
  return jsonDecode(notices.single['systemPayloadJson']! as String);
}

Future<void> _seedPlainPost(Connection writer) async {
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
SELECT '$_plainPost', user_id, title, description, status, kind, forward_policy,
       is_discoverable, published_at, expires_at
FROM public.beacon WHERE id = '$_post'
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
SELECT '$_plainRoot', '$_plainPost', author_id, body
FROM public.beacon_room_message WHERE id = '$_root'
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_plainRoot'
WHERE id = '$_plainPost'
''');
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
SELECT '$_plainPost', sender_id, recipient_id
FROM public.beacon_forward_edge WHERE beacon_id = '$_post'
''');
}
