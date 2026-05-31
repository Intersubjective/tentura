import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

/// Signed OAuth transaction payload stored in `__Host-tentura_oauth`.
class OAuthStatePayload {
  const OAuthStatePayload({
    required this.state,
    required this.codeVerifier,
    required this.nonce,
    required this.returnTo,
    this.inviteId,
  });

  final String state;
  final String codeVerifier;
  final String nonce;
  final String? inviteId;
  final String returnTo;
}

@Injectable(order: 3)
class OAuthStateCodec {
  const OAuthStateCodec(this._env);

  final Env _env;

  String encode(OAuthStatePayload payload) => JWT({
    'state': payload.state,
    'cv': payload.codeVerifier,
    'nonce': payload.nonce,
    if (payload.inviteId != null && payload.inviteId!.isNotEmpty)
      'invite': payload.inviteId,
    'returnTo': payload.returnTo,
  }).sign(
    _env.privateKey,
    algorithm: JWTAlgorithm.EdDSA,
    expiresIn: const Duration(seconds: kOAuthStateExpiresIn),
  );

  OAuthStatePayload decode(String token) {
    try {
      final jwt = JWT.verify(token, _env.publicKey);
      final map = jwt.payload as Map<String, dynamic>;
      final state = map['state'] as String? ?? '';
      final cv = map['cv'] as String? ?? '';
      final nonce = map['nonce'] as String? ?? '';
      final returnTo = map['returnTo'] as String? ?? '';
      if (state.isEmpty || cv.isEmpty || nonce.isEmpty) {
        throw const OidcStateMismatchException();
      }
      return OAuthStatePayload(
        state: state,
        codeVerifier: cv,
        nonce: nonce,
        inviteId: map['invite'] as String?,
        returnTo: returnTo,
      );
    } catch (e) {
      if (e is OidcStateMismatchException) rethrow;
      throw const OidcStateMismatchException();
    }
  }
}
