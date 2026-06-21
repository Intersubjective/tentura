import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/api/http/oauth_state_codec.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/env.dart';

void main() {
  late OAuthStateCodec codec;

  setUp(() {
    codec = OAuthStateCodec(Env(environment: Environment.test));
  });

  test('round-trip encodes OAuth transaction payload', () {
    const payload = OAuthStatePayload(
      state: 'state123',
      codeVerifier: 'verifier',
      nonce: 'nonce456',
      inviteId: 'Iabc',
      returnTo: 'https://app.example/',
    );
    final token = codec.encode(payload);
    final decoded = codec.decode(token);
    expect(decoded.state, payload.state);
    expect(decoded.codeVerifier, payload.codeVerifier);
    expect(decoded.nonce, payload.nonce);
    expect(decoded.inviteId, payload.inviteId);
    expect(decoded.returnTo, payload.returnTo);
    expect(decoded.linkAccountId, isNull);
  });

  test('round-trip encodes Settings link-mode linkAccountId', () {
    const payload = OAuthStatePayload(
      state: 'state123',
      codeVerifier: 'verifier',
      nonce: 'nonce456',
      returnTo: 'https://app.example/#/settings/sign-in-methods?linked=google',
      linkAccountId: 'Uabc123456789012345678901234567890',
    );
    final decoded = codec.decode(codec.encode(payload));
    expect(decoded.linkAccountId, payload.linkAccountId);
  });

  test('decode throws on tampered token', () {
    expect(
      () => codec.decode('not-a-jwt'),
      throwsA(isA<OidcStateMismatchException>()),
    );
  });
}
