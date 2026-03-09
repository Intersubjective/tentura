import 'package:injectable/injectable.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';

@Injectable(order: 3)
class AuthMiddleware {
  const AuthMiddleware(this._authCase);

  final AuthCase _authCase;

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
        if (request.headers.containsKey(kHeaderAuthorization)) {
          try {
            final jwt = _authCase.parseAndVerifyJwt(
              token: _extractAuthTokenFromHeaders(request.headers),
            );
            return innerHandler(request.change(context: {kContextJwtKey: jwt}));
          } catch (e) {
            print(e);
          }
        }
        return innerHandler(request);
      };

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
