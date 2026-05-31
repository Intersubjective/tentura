import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/api/http/cookies.dart';
import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/enum.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/session_case.dart';

@Injectable(order: 3)
class AuthMiddleware {
  AuthMiddleware(
    this._authCase,
    this._sessionCase,
  );

  final AuthCase _authCase;
  final SessionCase _sessionCase;

  ///
  /// Extract and verify bearer JWT.
  /// If ok, save it in request.context[kContextJwtKey]
  ///
  Middleware get verifyBearerJwt =>
      (innerHandler) => (request) async {
        if (request.headers.containsKey(kHeaderAuthorization)) {
          try {
            final jwt = _authCase.parseAndVerifyJwt(
              token: _extractAuthTokenFromHeaders(request.headers),
            );
            return innerHandler(request.change(context: {kContextJwtKey: jwt}));
          } catch (e) {
            final error = e.toString();
            print(error);
            return Response.unauthorized(error);
          }
        }
        return Response.unauthorized(null);
      };

  ///
  /// Check JWT, if success then place claims into request context
  ///
  Middleware get extractJwtClaims =>
      (innerHandler) => (request) {
        final jwt = _tryExtractJwt(request);
        if (jwt != null) {
          return innerHandler(request.change(context: {kContextJwtKey: jwt}));
        }
        return innerHandler(request);
      };

  /// Bearer JWT first, then session cookie (preview / optional-auth paths).
  Middleware get extractJwtOrSessionClaims =>
      (innerHandler) => (request) async {
        final bearerJwt = _tryExtractJwt(request);
        if (bearerJwt != null) {
          return innerHandler(
            request.change(context: {kContextJwtKey: bearerJwt}),
          );
        }
        final sessionToken = readCookie(
          request,
          _sessionCase.sessionCookieName(),
        );
        final accountId = await _sessionCase.resolveAccountId(sessionToken);
        if (accountId != null) {
          final jwt = JwtEntity(
            sub: accountId,
            roles: {UserRoles.user},
          )..validate();
          return innerHandler(request.change(context: {kContextJwtKey: jwt}));
        }
        return innerHandler(request);
      };

  JwtEntity? _tryExtractJwt(Request request) {
    if (!request.headers.containsKey(kHeaderAuthorization)) {
      return null;
    }
    try {
      return _authCase.parseAndVerifyJwt(
        token: _extractAuthTokenFromHeaders(request.headers),
      );
    } catch (e) {
      print(e);
      return null;
    }
  }

  //
  //
  String _extractAuthTokenFromHeaders(Map<String, String> headers) {
    const bearerPrefixLength = 'Bearer '.length;
    final authHeader = headers[kHeaderAuthorization];

    if (authHeader == null || authHeader.length <= bearerPrefixLength) {
      throw const AuthorizationHeaderWrongException();
    }

    final token = authHeader.substring(bearerPrefixLength).trim();
    if (token.isEmpty) {
      throw const AuthorizationHeaderWrongException();
    }

    return token;
  }
}
