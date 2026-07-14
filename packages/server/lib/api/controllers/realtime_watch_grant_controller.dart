import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/domain/use_case/realtime_watch_grant_case.dart';

import '_base_controller.dart';

/// Maps the authenticated REST contract; authorization and signing stay inward.
@Injectable(order: 3)
final class RealtimeWatchGrantController extends BaseController {
  const RealtimeWatchGrantController(
    super.env,
    this._grantCase,
  );

  final RealtimeWatchGrantCase _grantCase;

  @override
  Future<Response> handler(Request request) async {
    if (!env.realtimeWatchEnabled) {
      return Response(503, body: 'realtime watches disabled');
    }
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) return Response.unauthorized(null);

    try {
      final body = (await request.body.asJson as Map).cast<String, dynamic>();
      final scope = RealtimeWatchScope.fromWire(body['scope']);
      final rawSubjects = body['subjectIds'];
      final projection = body['projection'];
      if (scope == null ||
          rawSubjects is! List ||
          projection is! Map<String, dynamic> ||
          rawSubjects.any((subject) => subject is! String)) {
        throw const FormatException('Invalid watch grant request');
      }
      final descriptor = RealtimeWatchDescriptor(
        scope: scope,
        requestedSubjectIds: rawSubjects.cast<String>().toSet(),
        focusId: projection['focus'] as String?,
        context: projection['context'] as String?,
        positiveOnly: projection['positiveOnly'] as bool?,
        profileId: projection['profileId'] as String?,
        beaconId: projection['beaconId'] as String?,
      );
      final grant = await _grantCase.issue(
        viewerId: jwt.sub,
        descriptor: descriptor,
      );
      return Response.ok(
        jsonEncode({
          'grant': grant.token,
          'scope': grant.scope.name,
          'subjectIds': grant.authorizedSubjectIds.toList()..sort(),
          'expiresAt': grant.expiresAt.toIso8601String(),
          'protocolVersion': RealtimeWatchGrantCase.protocolVersion,
        }),
        headers: {kHeaderContentType: 'application/json'},
      );
    } on FormatException catch (error) {
      return Response.badRequest(
        body: jsonEncode({'error': error.message}),
        headers: {kHeaderContentType: 'application/json'},
      );
    } on Object {
      return Response.internalServerError();
    }
  }
}
