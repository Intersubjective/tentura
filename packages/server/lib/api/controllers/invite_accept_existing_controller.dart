import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '_base_controller.dart';

/// `POST /api/v2/invite/<code>/accept-as-existing` — an already-authenticated
/// user befriends the invite issuer (beacon forwarded when present). Guarded by
/// `verifyBearerJwt`; single-use code, retry-safe (see
/// `InvitationCase.acceptAsExisting`). Never creates an account.
@Injectable(order: 3)
final class InviteAcceptExistingController extends BaseController {
  const InviteAcceptExistingController(
    super.env,
    this._invitationCase,
  );

  final InvitationCase _invitationCase;

  @override
  Future<Response> handler(Request request) async {
    final code = request.params['code'] ?? '';
    if (code.isEmpty) {
      return Response.badRequest(body: 'missing invite code');
    }

    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) {
      return Response.unauthorized(null);
    }

    try {
      final ok = await _invitationCase.acceptAsExisting(
        code: code,
        userId: jwt.sub,
      );
      return Response.ok(
        jsonEncode({'ok': ok}),
        headers: {kHeaderContentType: 'application/json'},
      );
    } on IdNotFoundException catch (e) {
      return Response.notFound(
        jsonEncode(e.toMap),
        headers: {kHeaderContentType: 'application/json'},
      );
    } on ExceptionBase catch (e) {
      return Response.badRequest(
        body: jsonEncode(e.toMap),
        headers: {kHeaderContentType: 'application/json'},
      );
    } catch (_) {
      return Response.internalServerError();
    }
  }
}
