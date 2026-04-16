import 'dart:convert';
import 'package:test/test.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_server/env.dart';

void main() {
  group('Read keys from PEM', () {
    const envPublicKey =
        r'-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA2CmIb3Ho2eb6m8WIog6KiyzCY05sbyX04PiGlH5baDw=\n-----END PUBLIC KEY-----';
    const envPrivateKey =
        r'-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIN3rCo3wCksyxX4qBYAC1vFr51kx/Od78QVrRLOV1orF\n-----END PRIVATE KEY-----';

    test('Read PEM', () {
      expect(EdDSAPublicKey.fromPEM(Env.kJwtPublicKey).bytes, isNotEmpty);

      expect(EdDSAPrivateKey.fromPEM(Env.kJwtPrivateKey).seed, isNotEmpty);

      expect(
        EdDSAPublicKey.fromPEM(envPublicKey.replaceAll(r'\n', '\n')).bytes,
        isNotEmpty,
      );

      expect(
        EdDSAPrivateKey.fromPEM(
          envPrivateKey.replaceAll(r'\n', '\n'),
        ).seed,
        isNotEmpty,
      );
    });
  });

  group('Test of JWT utils', () {
    test('issue / verify AuthRequest', () {
      final authRequestToken = issueAuthRequestToken(kPublicKey);
      final jwt = verifyAuthRequest(token: authRequestToken);
      print(jwt.payload);

      expect(
        (jwt.payload as Map)['pk'],
        equals(base64UrlEncode(kPublicKey.bytes)),
      );
    });
  });
}

final kPublicKey = EdDSAPublicKey.fromPEM(
  Env.kJwtPublicKey.replaceAll(r'\n', '\n'),
);

final kPrivateKey = EdDSAPrivateKey.fromPEM(
  Env.kJwtPrivateKey.replaceAll(r'\n', '\n'),
);

String issueAuthRequestToken(EdDSAPublicKey publicKey) =>
    JWT({'pk': base64UrlEncode(publicKey.bytes)}).sign(
      kPrivateKey,
      algorithm: JWTAlgorithm.EdDSA,
      expiresIn: const Duration(seconds: kAuthJwtExpiresIn),
    );

JWT verifyAuthRequest({required String token}) {
  final jwtDecoded = JWT.decode(token);

  if (jwtDecoded.header?['alg'] != 'EdDSA') {
    throw JWTInvalidException('Wrong JWT algo!');
  }

  final authRequestToken = (jwtDecoded.payload as Map)['pk'] as String;

  return JWT.verify(token, EdDSAPublicKey(base64Decode(authRequestToken)));
}
