import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '_base_controller.dart';

/// `GET /api/v2/invite/<code>/preview` — JSON preview of an invite for the
/// caller, decided before any UI loads. Guarded by `extractJwtClaims`
/// (non-failing) so anonymous vs existing-user is distinguishable.
@Injectable(order: 3)
final class InvitePreviewController extends BaseController {
  const InvitePreviewController(
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
    final callerUserId =
        (jwt == null || jwt.sub.isEmpty || jwt.roles.contains(UserRoles.anon))
        ? null
        : jwt.sub;
    try {
      final result = await _invitationCase.preview(
        code: code,
        callerUserId: callerUserId,
      );
      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {kHeaderContentType: 'application/json'},
      );
    } catch (_) {
      return Response.internalServerError();
    }
  }
}
