import 'dart:convert';
import 'package:ed25519_edwards/ed25519_edwards.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura/consts.dart';

import 'credentials.dart';
import 'remote_api_client_base.dart';

export 'package:tentura_root/domain/entity/auth_request_intent.dart'
    show AuthRequestIntent;

part 'auth_box.freezed.dart';

typedef AuthTokenFetcher =
    Future<Credentials> Function(GqlFetcher fetcher, String authRequestToken);

@freezed
abstract class AuthBox with _$AuthBox {
  const factory AuthBox({
    required EdDSAPublicKey publicKey,
    required EdDSAPrivateKey privateKey,
    required AuthTokenFetcher authTokenFetcher,
    Credentials? credentials,
  }) = _AuthBox;

  factory AuthBox.fromSeed({
    required String seed,
    required AuthTokenFetcher authTokenFetcher,
  }) {
    final privateKey = newKeyFromSeed(base64Decode(seed));
    return AuthBox(
      authTokenFetcher: authTokenFetcher,
      privateKey: EdDSAPrivateKey(privateKey.bytes),
      publicKey: EdDSAPublicKey(public(privateKey).bytes),
    );
  }

  const AuthBox._();

  bool get hasValidToken => credentials?.hasValidToken ?? false;

  String getAuthRequestToken(AuthRequestIntent intent) => JWT({
    intent.keyCname: intent.cname,
    AuthRequestIntent.keyPublicKey: base64UrlEncode(publicKey.bytes),
    if (intent is AuthRequestIntentSignUp && intent.invitationCode.isNotEmpty)
      AuthRequestIntentSignUp.keyCode: intent.invitationCode,
  }).sign(
    privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(seconds: kAuthJwtExpiresIn),
  );

  Future<Credentials> fetchCredentials(GqlFetcher fetcher) => authTokenFetcher(
    fetcher,
    getAuthRequestToken(const AuthRequestIntentSignIn()),
  );
}
