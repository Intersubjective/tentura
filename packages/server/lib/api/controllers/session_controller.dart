import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

import '../http/cookies.dart';
import '_base_controller.dart';

/// Session endpoints for the app-host TMB cookie model.
@Injectable(order: 3)
final class SessionController extends BaseController {
  const SessionController(
    super.env,
    this._sessionCase,
  );

  final SessionCase _sessionCase;

  /// `POST /api/v2/session/access-token` — mint Bearer from session cookie.
  Future<Response> accessToken(Request request) async {
    final token = readCookie(request, _sessionCase.sessionCookieName());
    final accountId = await _sessionCase.resolveAccountId(token);
    if (accountId == null) {
      return Response.unauthorized('session required');
    }
    final body = await _sessionCase.accessTokenForAccount(accountId);
    return Response.ok(
      jsonEncode(body),
      headers: {
        kHeaderContentType: kContentApplicationJson,
        kHeaderCacheControl: kCacheControlNoStore,
      },
    );
  }

  /// `POST /api/v2/session/logout` — revoke session + clear cookie.
  Future<Response> logout(Request request) async {
    final token = readCookie(request, _sessionCase.sessionCookieName());
    await _sessionCase.revokeSession(token);
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: withSetCookie(
        {
          kHeaderContentType: kContentApplicationJson,
          kHeaderCacheControl: kCacheControlNoStore,
        },
        buildClearCookie(_sessionCase.sessionCookieName()),
      ),
    );
  }

  /// `POST /api/v2/session/from-bearer` — seed sign-in converges to cookie.
  Future<Response> fromBearer(Request request) async {
    final jwt = request.context[kContextJwtKey] as JwtEntity?;
    if (jwt == null || jwt.sub.isEmpty) {
      return Response.unauthorized(null);
    }
    final sessionToken = await _sessionCase.createSession(
      accountId: jwt.sub,
      credentialId: jwt.credentialId.isEmpty ? null : jwt.credentialId,
    );
    final maxAge = _sessionCase.sessionCookieMaxAge().inSeconds;
    return Response.ok(
      jsonEncode({'ok': true}),
      headers: withSetCookie(
        {
          kHeaderContentType: kContentApplicationJson,
          kHeaderCacheControl: kCacheControlNoStore,
        },
        buildSetCookie(
          name: _sessionCase.sessionCookieName(),
          value: sessionToken,
          maxAgeSeconds: maxAge,
        ),
      ),
    );
  }

  @override
  Future<Response> handler(Request request) =>
      throw UnsupportedError('use accessToken/logout/fromBearer');
}
