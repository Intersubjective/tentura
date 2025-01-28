import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/consts.dart';

final publicKey = EdDSAPublicKey.fromPEM(
  kJwtPublicKey.replaceAll(r'\n', '\n'),
);

final privateKey = EdDSAPrivateKey.fromPEM(
  kJwtPrivateKey.replaceAll(r'\n', '\n'),
);

///
/// Returns bearer token extracted from Request headers
///
String extractAuthTokenFromHeaders(Map<String, String> headers) {
  final authHeader = headers[kHeaderAuthorization];
  if (authHeader == null || authHeader.length <= _bearerPrefixLength) {
    throw JWTInvalidException('Wrong Authorization header');
  }

  final token = headers[kHeaderAuthorization]
      ?.substring(
        _bearerPrefixLength,
      )
      .trim();
  if (token == null || token.isEmpty) {
    throw JWTInvalidException('Wrong Authorization header');
  }

  return token;
}

///
/// Returns parsed and verified client`s JWT with auth request
///
JWT verifyAuthRequest({
  required String token,
}) {
  final jwtDecoded = JWT.decode(token);

  if (jwtDecoded.header?['alg'] != 'EdDSA') {
    throw JWTInvalidException('Wrong JWT algo!');
  }

  final exp = (jwtDecoded.payload as Map)['exp'];
  final expiresIn = exp is int ? exp * 1000 : 0;

  if (expiresIn <= 0 || expiresIn > kAuthJwtExpiresIn) {
    throw JWTInvalidException('Wrong JWT exp value!');
  }

  final authRequestToken = base64.normalize(
    (jwtDecoded.payload as Map)['pk'] as String,
  );

  return JWT.verify(
    token,
    EdDSAPublicKey(base64Decode(authRequestToken)),
  );
}

///
/// Parse and verify JWT issued before
///
JWT verifyJwt({
  required String token,
}) =>
    JWT.verify(
      token,
      publicKey,
    );

///
/// Create Oauth2 response
///
Map<String, Object> issueJwt({
  required String subject,
  Map<String, Object> payload = const {},
}) =>
    {
      'subject': subject,
      'token_type': 'bearer',
      'expires_in': kJwtExpiresIn,
      'access_token': JWT(
        payload,
        subject: subject,
      ).sign(
        privateKey,
        algorithm: JWTAlgorithm.EdDSA,
        expiresIn: const Duration(seconds: kJwtExpiresIn),
      ),
    };

const _bearerPrefixLength = 'Bearer '.length;
