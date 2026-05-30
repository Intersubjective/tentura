import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';

import '_base_controller.dart';

/// `POST /api/v2/invite/<code>/accept-as-new` — anonymous signup that consumes
/// the invite: creates the account + its `ed25519_device` credential, befriends
/// the issuer, and forwards the beacon when present (all in
/// `AuthCase.signUpWithInvite` → `createInvited`). Returns the oauth2 session
/// map, same shape as the GraphQL `signUp` mutation.
///
/// No bearer is required (the caller is anonymous). Rate-limiting per IP is a
/// follow-up — invite slots are the natural limiter for now.
@Injectable(order: 3)
final class InviteAcceptNewController extends BaseController {
  const InviteAcceptNewController(
    super.env,
    this._authCase,
  );

  final AuthCase _authCase;

  @override
  Future<Response> handler(Request request) async {
    final code = request.params['code'] ?? '';
    if (code.isEmpty) {
      return Response.badRequest(body: 'missing invite code');
    }

    final Map<String, dynamic> body;
    try {
      body = (await request.body.asJson as Map).cast<String, dynamic>();
    } catch (_) {
      return Response.badRequest(body: 'invalid JSON body');
    }

    final authRequestToken = body['authRequestToken'] as String?;
    final displayName = body['displayName'] as String?;
    final handle = body['handle'] as String?;
    if (authRequestToken == null ||
        authRequestToken.isEmpty ||
        displayName == null ||
        displayName.isEmpty) {
      return Response.badRequest(
        body: 'authRequestToken and displayName are required',
      );
    }

    try {
      final jwt = await _authCase.signUpWithInvite(
        authRequestToken: authRequestToken,
        invitationId: code,
        displayName: displayName,
        handle: handle,
      );
      return Response.ok(
        jsonEncode(jwt.asOauth2Map),
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
