@Tags(['pg'])
@Timeout(Duration(minutes: 3))
library;

// Public API contract: beaconForwardMarkRead(id) stamps the CALLER's own
// forward edge(s) for the Request as read, whatever their involvement access
// is. The sender sees it as myForwardedRecipients.readAt and is the only
// person notified.
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart' as pg;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/api/http/request_context_io_adapter.dart';
import 'package:tentura_server/app/di.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import '../../../support/pg_notification_recorder.dart';
import '../../../support/pg_test_public_keys.dart';
import '../../../support/session_database_di_harness.dart';

const _author = 'Umarkreadauthor';
const _sender = 'Umarkreadsender';
const _secondSender = 'Umarkreadsendr2';
const _plain = 'Umarkreadplain1';
const _stranger = 'Umarkreadstrang';

const _markRead = r'''
mutation BeaconForwardMarkRead($id: String!) {
  beaconForwardMarkRead(id: $id)
}
''';
const _involvement = r'''
query SenderInvolvement($id: String!) {
  beaconInvolvement(id: $id) {
    myForwardedRecipients { edgeId recipientId readAt }
  }
}
''';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FORWARD_MARK_READ_TEST_DB',
    defaultNamePrefix: 'tentura_test_forward_mark_read',
  );
  final unavailable = await pgSkipReason(target);
  if (unavailable != null) {
    test('forward mark-read requires reachable Postgres', () {
      fail(unavailable);
    });
    return;
  }

  group('Marking a received Request as read', () {
    late DisposablePgWriterSession session;
    late pg.Connection listener;
    late PgNotificationRecorder recorder;
    late GraphqlController controller;
    var beaconSeq = 0;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      final db = target.databaseEnv;
      final env = Env(
        environment: Environment.dev,
        serverUri: Uri.parse('http://127.0.0.1:2080'),
        publicOrigin: 'http://127.0.0.1:2080',
        publicKey: Env.kJwtPublicKey,
        privateKey: Env.kJwtPrivateKey,
        pgHost: db.pgHost,
        pgPort: db.pgPort,
        pgDatabase: db.pgDatabase,
        pgUsername: db.pgUsername,
        pgPassword: db.pgPassword,
        maxConnectionCount: 8,
        workersCount: 1,
        printEnv: false,
        isDebugModeOn: false,
      );
      getIt.skipDoubleRegistration = true;
      await configureSessionDatabaseTestGraph(env);
      controller = GraphqlController(env);
      for (final (i, id) in [
        _author,
        _sender,
        _secondSender,
        _plain,
        _stranger,
      ].indexed) {
        await session.writer.execute(
          pg.Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key) '
            'VALUES (@id, @id, @key)',
          ),
          parameters: {'id': id, 'key': pgTestPublicKey('markread', i + 1)},
        );
      }
      listener = await pg.Connection.open(
        db.pgEndpoint,
        settings: db.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      recorder = PgNotificationRecorder(listener.channels['entity_changes']);
    });

    tearDownAll(() async {
      await recorder.cancel();
      await listener.close();
      getIt.skipDoubleRegistration = false;
      await getIt.reset();
      await tearDownDisposablePgWriter(session: session);
    });

    Future<void> barrier(String token) => session.writer.execute(
      pg.Sql.named("SELECT pg_notify('entity_changes', @payload)"),
      parameters: {
        'payload': jsonEncode({'entity': 'barrier', 'id': token}),
      },
    );

    Future<Map<String, dynamic>> post(
      String viewer,
      String query,
      String operation,
      Map<String, Object?> variables,
    ) async {
      final handler = requestContextIoAdapter(
        (request) => controller.handler(
          request.change(context: {kContextJwtKey: JwtEntity(sub: viewer)}),
        ),
      );
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/v2/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query': query,
            'operationName': operation,
            'variables': variables,
          }),
        ),
      );
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    /// A fresh Request by [_author] forwarded to [_plain] by each of
    /// [senders]. [_plain] has no help offer and no participant row.
    Future<({String beaconId, Map<String, String> edgeBySender})> seed(
      List<String> senders,
    ) async {
      final beaconId = 'Bmarkread${(beaconSeq++).toString().padLeft(4, '0')}';
      await session.writer.execute(
        pg.Sql.named(
          'INSERT INTO public.beacon (id, user_id, title, description, status) '
          "VALUES (@id, @author, 'Request', '', 0)",
        ),
        parameters: {'id': beaconId, 'author': _author},
      );
      final edges = <String, String>{};
      for (final (i, sender) in senders.indexed) {
        final edgeId = 'F${beaconId.substring(1)}$i';
        await session.writer.execute(
          pg.Sql.named(
            'INSERT INTO public.beacon_forward_edge '
            '(id, beacon_id, sender_id, recipient_id) '
            'VALUES (@e, @b, @s, @r)',
          ),
          parameters: {'e': edgeId, 'b': beaconId, 's': sender, 'r': _plain},
        );
        edges[sender] = edgeId;
      }
      return (beaconId: beaconId, edgeBySender: edges);
    }

    Future<DateTime?> readAt(String edgeId) async {
      final rows = await session.writer.execute(
        pg.Sql.named(
          'SELECT recipient_read_at FROM public.beacon_forward_edge '
          'WHERE id = @id',
        ),
        parameters: {'id': edgeId},
      );
      return rows.single.single as DateTime?;
    }

    Future<List<Map<String, dynamic>>> readHints(String beaconId) async {
      await recorder.flush(sendBarrier: barrier);
      return recorder.messages
          .where((m) => m['entity'] == 'forward' && m['id'] == beaconId)
          .toList();
    }

    Future<Map<String, dynamic>> markRead(String viewer, String beaconId) =>
        post(viewer, _markRead, 'BeaconForwardMarkRead', {'id': beaconId});

    test(
      "a plain recipient opening stamps the sender's sent list once, a "
      'repeat is a no-op, and only the sender is notified',
      () async {
        final seeded = await seed([_author]);
        final edgeId = seeded.edgeBySender[_author]!;
        expect(await readAt(edgeId), isNull);
        await recorder.drain(sendBarrier: barrier);

        final first = await markRead(_plain, seeded.beaconId);
        expect(first['errors'], isNull, reason: jsonEncode(first));
        final stamp = await readAt(edgeId);
        expect(stamp, isNotNull, reason: 'the edge is stamped by the open');

        final senderView = await post(
          _author,
          _involvement,
          'SenderInvolvement',
          {'id': seeded.beaconId},
        );
        expect(senderView['errors'], isNull, reason: jsonEncode(senderView));
        final recipients =
            ((senderView['data'] as Map)['beaconInvolvement']
                    as Map)['myForwardedRecipients']
                as List;
        expect(recipients.single, containsPair('recipientId', _plain));
        expect(
          (recipients.single as Map)['readAt'],
          isNotNull,
          reason: 'the sender sees the recipient as having read the Request',
        );

        final hints = await readHints(seeded.beaconId);
        expect(hints, hasLength(1), reason: 'exactly one notification');
        expect(hints.single['user_ids'], [_author]);

        recorder.messages.clear();
        final second = await markRead(_plain, seeded.beaconId);
        expect(second['errors'], isNull, reason: jsonEncode(second));
        expect(await readAt(edgeId), stamp, reason: 'original stamp is kept');
        expect(
          await readHints(seeded.beaconId),
          isEmpty,
          reason: 'a repeat open writes and notifies nothing',
        );
      },
    );

    test(
      'a person who was not sent the Request stamps nothing and notifies '
      'nobody',
      () async {
        final seeded = await seed([_sender]);
        final edgeId = seeded.edgeBySender[_sender]!;
        await recorder.drain(sendBarrier: barrier);

        for (final viewer in [_stranger, _sender, _author]) {
          await markRead(viewer, seeded.beaconId);
          expect(
            await readAt(edgeId),
            isNull,
            reason: '$viewer is not the recipient of that edge',
          );
        }
        expect(await readHints(seeded.beaconId), isEmpty);
      },
    );

    test(
      'a recipient reached by two forwarders stamps each edge and each '
      'sender hears only about their own',
      () async {
        final seeded = await seed([_sender, _secondSender]);
        await recorder.drain(sendBarrier: barrier);

        final result = await markRead(_plain, seeded.beaconId);
        expect(result['errors'], isNull, reason: jsonEncode(result));
        for (final edgeId in seeded.edgeBySender.values) {
          expect(await readAt(edgeId), isNotNull);
        }
        final hints = await readHints(seeded.beaconId);
        expect(
          hints.map((h) => (h['user_ids'] as List).cast<String>()).toList(),
          unorderedEquals([
            [_sender],
            [_secondSender],
          ]),
        );
      },
    );
  });
}
