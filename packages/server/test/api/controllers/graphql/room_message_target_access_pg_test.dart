@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/consts.dart' show kContextJwtKey;
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/env.dart' show Env;
import 'package:test/test.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/post_bud_privacy_fixture.dart';
import '../../../support/session_database_di_harness.dart';

const _member = PostBudPrivacyFixture.anna;
const _uninvited = PostBudPrivacyFixture.carol;
const _otherOwner = PostBudPrivacyFixture.helper;
const _otherRequest = 'BtargetOther0';
const _ownMessage = 'RtargetOwn000';
const _otherMessage = 'RtargetOther0';
const _missingMessage = 'RtargetAbsent';

const _foreignChats = [
  (
    label: 'the readable parent Post',
    beaconId: PostBudPrivacyFixture.post,
    messageId: PostBudPrivacyFixture.postRoot,
    owner: _member,
    isReadable: true,
  ),
  (
    label: 'an unreadable private Request',
    beaconId: _otherRequest,
    messageId: _otherMessage,
    owner: _otherOwner,
    isReadable: false,
  ),
];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ROOM_MESSAGE_TARGET_ACCESS_TEST_DB',
    defaultNamePrefix: 'tentura_test_room_message_target_access',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late BeaconRoomCase roomCase;
  late Handler api;
  late String requestId;

  setUpAll(() async {
    final previousWarningSetting =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
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

    final fixture = PostBudPrivacyFixture(session.writer, database, env);
    await fixture.reset();
    await fixture.seedPost();
    requestId = await fixture.bud();

    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable, published_at)
VALUES (@id, @owner, 'Private planning', '', 0, 0, false, now())
'''),
      parameters: {'id': _otherRequest, 'owner': _otherOwner},
    );
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES
  (@ownMessage, @requestedBeacon, @member, 'Meet at the greenhouse'),
  (@otherMessage, @otherBeacon, @otherOwner, 'Discuss the supplies here')
'''),
      parameters: {
        'ownMessage': _ownMessage,
        'requestedBeacon': requestId,
        'member': _member,
        'otherMessage': _otherMessage,
        'otherBeacon': _otherRequest,
        'otherOwner': _otherOwner,
      },
    );

    addTearDown(() async {
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
    });
    await configureSessionDatabaseTestGraph(env);
    roomCase = getIt<BeaconRoomCase>();
    final router = Router().plus
      ..post(
        '/api/v2/graphql',
        getIt<GraphqlController>().handler,
      );
    api = router.call;
  });

  Future<Map<String, Object?>?> lookup(
    String viewer,
    String messageId, {
    String? beaconId,
  }) => roomCase.roomMessageTarget(
    beaconId: beaconId ?? requestId,
    messageId: messageId,
    userId: viewer,
  );

  Future<UnauthorizedException> denialForOwnChat() async {
    try {
      await lookup(_uninvited, _ownMessage);
    } on UnauthorizedException catch (error) {
      return error;
    }
    fail('An uninvited viewer must be denied a message in the requested Chat');
  }

  Matcher sameDenialAs(UnauthorizedException error) => throwsA(
    isA<UnauthorizedException>()
        .having((e) => e.code.codeNumber, 'code', error.code.codeNumber)
        .having((e) => e.description, 'description', error.description),
  );

  Future<({int status, Map<String, Object?> payload})> postTarget(
    String viewer,
    String messageId, {
    String? beaconId,
  }) async {
    final response = await api(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        context: {kContextJwtKey: JwtEntity(sub: viewer)},
        body: jsonEncode({
          'query':
              '''
{
  roomMessageTarget(beaconId: "${beaconId ?? requestId}", messageId: "$messageId") { id }
}
''',
        }),
      ),
    );
    return (
      status: response.statusCode,
      payload:
          jsonDecode(await response.readAsString()) as Map<String, Object?>,
    );
  }

  group('Chat message lookup for an uninvited Post member', () {
    test(
      'a missing ID receives the same denial as a message in the Chat',
      () async {
        final denial = await denialForOwnChat();
        await expectLater(
          lookup(_uninvited, _missingMessage),
          sameDenialAs(denial),
        );
      },
    );

    for (final chat in _foreignChats) {
      test(
        'a message in ${chat.label} receives the same denial as a message in the requested Chat',
        () async {
          final denial = await denialForOwnChat();
          expect(
            await lookup(chat.owner, chat.messageId, beaconId: chat.beaconId),
            containsPair('id', chat.messageId),
          );
          final sourceLookup = lookup(
            _uninvited,
            chat.messageId,
            beaconId: chat.beaconId,
          );
          if (chat.isReadable) {
            expect(await sourceLookup, containsPair('id', chat.messageId));
          } else {
            await expectLater(
              sourceLookup,
              throwsA(isA<UnauthorizedException>()),
            );
          }

          await expectLater(
            lookup(_uninvited, chat.messageId),
            sameDenialAs(denial),
          );
        },
      );
    }
  });

  group('Chat message lookup for a Request member', () {
    for (final chat in _foreignChats) {
      test(
        'a message in ${chat.label} is absent from the requested Chat',
        () async {
          expect(
            await lookup(_member, _ownMessage),
            allOf(
              containsPair('id', _ownMessage),
              containsPair('beaconId', requestId),
            ),
          );
          final sourceLookup = lookup(
            _member,
            chat.messageId,
            beaconId: chat.beaconId,
          );
          if (chat.isReadable) {
            expect(await sourceLookup, containsPair('id', chat.messageId));
          } else {
            await expectLater(
              sourceLookup,
              throwsA(isA<UnauthorizedException>()),
            );
          }
          expect(await lookup(_member, _missingMessage), isNull);
          expect(await lookup(_member, chat.messageId), isNull);
        },
      );
    }
  });

  group('GraphQL Chat message lookup', () {
    test(
      'an uninvited Post member gets identical denials for private and unknown Request IDs',
      () async {
        final private = await postTarget(_uninvited, _ownMessage);
        final unknown = await postTarget(
          _uninvited,
          _ownMessage,
          beaconId: BeaconEntity.newId,
        );

        expect(private.status, 200);
        expect(private.payload, {
          'errors': [
            {
              'message': 'Room or item thread access required',
              'extensions': {'code': '1102', 'path': ''},
            },
          ],
        });
        expect(unknown.status, private.status);
        expect(unknown.payload, private.payload);
      },
    );

    for (final chat in _foreignChats) {
      test(
        'an uninvited viewer gets the same error for a missing ID and a message in ${chat.label}',
        () async {
          final missing = await postTarget(_uninvited, _missingMessage);
          final foreign = await postTarget(_uninvited, chat.messageId);
          expect(foreign.status, missing.status);
          for (final response in [missing, foreign]) {
            final data = response.payload['data'] as Map<String, Object?>?;
            expect(data?['roomMessageTarget'], isNull);
          }
          expect(foreign.payload['errors'], missing.payload['errors']);
          expect(missing.payload['errors'], [
            allOf(
              containsPair('message', isA<String>()),
              containsPair(
                'extensions',
                containsPair(
                  'code',
                  '${const UnauthorizedException().code.codeNumber}',
                ),
              ),
            ),
          ]);
        },
      );

      test(
        'a Request member gets a null target without errors for a message in ${chat.label}',
        () async {
          final missing = await postTarget(_member, _missingMessage);
          final foreign = await postTarget(_member, chat.messageId);
          expect(missing.status, 200);
          expect(missing.payload, {
            'data': {'roomMessageTarget': null},
          });
          expect(foreign.status, missing.status);
          expect(foreign.payload, missing.payload);
        },
      );
    }
  });
}
