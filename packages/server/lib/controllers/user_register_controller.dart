import 'dart:convert';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
import 'package:shelf_plus/shelf_plus.dart';

import '../data/database/database.dart';
import '../utils/id.dart';
import '../utils/jwt.dart';

Future<Response> userRegisterController(Request request) async {
  try {
    final jwt = verifyAuthRequest(
      token: extractAuthToken(
        headers: request.headers,
      ),
    );
    final publicKey = (jwt.payload as Map)['pk'] as String;
    final userId = generateId();

    await GetIt.I<Database>().managers.user.create(
          (o) => o(
            id: userId,
            publicKey: publicKey,
          ),
          mode: InsertMode.insert,
        );

    return Response.ok(
      jsonEncode(issueJwt(subject: userId)),
    );
  } catch (e) {
    GetIt.I<Logger>().e(e);

    return Response.unauthorized(e);
  }
}
