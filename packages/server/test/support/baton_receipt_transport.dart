import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';

import 'baton_receipt_fixture.dart';
import 'disposable_pg_target.dart';

// An HTTP boundary for Ferry. The response is produced by the production
// GraphQL resolver reading the receipts committed by the room actions.
Future<void> main() async {
  final fixture = BatonReceiptFixture(
    DisposablePgTarget.fromNamedEnvironment(
      envVarName: 'TENTURA_BATON_RECEIPT_TRANSPORT_TEST_DB',
      defaultNamePrefix: 'tentura_test_baton_receipt_wire',
    ),
  );
  await fixture.open(activityStream: true);
  HttpServer? server;
  try {
    final joined = await fixture.propose(batonJoinedRequest);
    await fixture.answer(joined, accept: true);
    final pairWithExcerpt = await fixture.propose(batonPairWithExcerptRequest);
    await fixture.answer(pairWithExcerpt, accept: true);
    await fixture.pick(pairWithExcerpt);
    final declined = await fixture.propose(batonDeclinedRequest);
    await fixture.answer(declined, accept: false);
    final pair = await fixture.propose(
      batonPairWithoutExcerptRequest,
      withExcerpt: false,
    );
    await fixture.answer(pair, accept: true);
    await fixture.pick(pair);
    final solo = await fixture.propose(
      batonSoloWithoutExcerptRequest,
      pair: false,
      withExcerpt: false,
    );
    await fixture.pick(solo);
    await fixture.drainChannels();

    const roomRequest = 'BbatonRoom001';
    RoomBaton? roomBaton;
    final done = Completer<void>();
    server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
      ..listen((request) async {
        try {
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/close') {
            request.response.write('{}');
            await request.response.close();
            done.complete();
            return;
          }
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          if (request.uri.path == '/room') {
            final baton = roomBaton ??= await fixture.propose(
              roomRequest,
              withExcerpt: false,
            );
            final pick = body['pick'] as String?;
            if (pick == null) {
              await fixture.answer(baton, accept: true);
              // A later message means the outcome is visible as a system line.
              await fixture.room.insertRoomMessage(
                beaconId: roomRequest,
                authorId: batonCarol,
                body: 'Ready to help',
              );
            } else {
              await fixture.pick(baton, userId: pick);
            }
            final rows = await fixture.room.listMessagesEnriched(
              beaconId: roomRequest,
              viewerUserId: batonAnna,
            );
            request.response.write(jsonEncode({'messages': rows}));
            return;
          }
          final result = await fixture.schema.parseAndExecute(
            body['query'] as String,
            variableValues: (body['variables'] as Map).cast<String, dynamic>(),
            globalVariables: {
              kGlobalInputQueryJwt: JwtEntity(
                sub: request.uri.queryParameters['viewer']!,
              ),
            },
          );
          request.response.write(jsonEncode({'data': result}));
        } on Object catch (error) {
          request.response.write(
            jsonEncode({
              'errors': [
                {'message': error.toString()},
              ],
            }),
          );
        } finally {
          await request.response.close();
        }
      });
    stdout.writeln(
      'TENTURA_RECEIPT_TRANSPORT ${jsonEncode({'ready': server.port})}',
    );
    await done.future;
  } finally {
    await server?.close();
    await fixture.close();
  }
}
