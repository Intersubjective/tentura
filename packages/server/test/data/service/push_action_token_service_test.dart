import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/push_action_token_service.dart';
import 'package:tentura_server/domain/plan/push_action.dart';
import 'package:tentura_server/env.dart';

/// Plan push buttons (#220 §5.9): the signed action token.
void main() {
  final env = Env();
  final tokens = PushActionTokenService(env);

  const done = PushActionClaims(
    accountId: 'Uacc',
    action: PushAction.done,
    beaconId: 'Bone',
    stepId: 'PS000000000001',
  );
  const ack = PushActionClaims(
    accountId: 'Uacc',
    action: PushAction.ack,
    beaconId: 'Bone',
    seq: 7,
  );

  test('round-trips a «Готово» token', () {
    final claims = tokens.verify(tokens.sign(done))!;
    expect(claims.accountId, 'Uacc');
    expect(claims.action, PushAction.done);
    expect(claims.beaconId, 'Bone');
    expect(claims.stepId, 'PS000000000001');
    expect(claims.seq, isNull);
  });

  test('round-trips a «Понятно» token', () {
    final claims = tokens.verify(tokens.sign(ack))!;
    expect(claims.action, PushAction.ack);
    expect(claims.seq, 7);
    expect(claims.stepId, isNull);
  });

  test('has no subject, so it can never pass as an access token', () {
    final decoded = JWT.decode(tokens.sign(done));
    expect(decoded.subject, isNull);
    expect((decoded.payload as Map)['sub'], isNull);
  });

  test('expires within 24 hours, even when asked for longer', () {
    final payload =
        JWT.decode(tokens.sign(done, ttl: const Duration(days: 9))).payload
            as Map;
    final life = (payload['exp'] as int) - (payload['iat'] as int);
    expect(life, lessThanOrEqualTo(24 * 3600));
  });

  test('rejects a tampered token', () {
    final token = tokens.sign(done);
    final parts = token.split('.');
    final otherBody = tokens.sign(ack).split('.')[1];
    expect(tokens.verify('${parts[0]}.$otherBody.${parts[2]}'), isNull);
    expect(tokens.verify('$token x'), isNull);
    expect(tokens.verify(''), isNull);
    expect(tokens.verify('not-a-jwt'), isNull);
  });

  test('rejects an expired token', () {
    final expired = JWT(
      {
        'purpose': 'push_action',
        'pacc': 'Uacc',
        'act': 'done',
        'bid': 'Bone',
        'sid': 'PS000000000001',
        'exp':
            DateTime.now()
                .subtract(const Duration(minutes: 1))
                .millisecondsSinceEpoch ~/
            1000,
      },
      issuer: env.publicOrigin,
      audience: Audience.one('tentura:push_action'),
    ).sign(env.privateKey, algorithm: JWTAlgorithm.EdDSA);
    expect(tokens.verify(expired), isNull);
  });

  test('rejects tokens minted for other purposes with the same keys', () {
    final accessLike =
        JWT(
          {'x-hasura-roles': 'user'},
          subject: 'Uacc',
          issuer: env.publicOrigin,
        ).sign(
          env.privateKey,
          algorithm: JWTAlgorithm.EdDSA,
          expiresIn: const Duration(minutes: 5),
        );
    expect(tokens.verify(accessLike), isNull);

    final linkToken =
        JWT(
          {'purpose': 'google_link', 'lacc': 'Uacc'},
          issuer: env.publicOrigin,
          audience: Audience.one('tentura:google_link'),
        ).sign(
          env.privateKey,
          algorithm: JWTAlgorithm.EdDSA,
          expiresIn: const Duration(minutes: 5),
        );
    expect(tokens.verify(linkToken), isNull);
  });

  test('rejects a token signed by another key', () {
    final other = PushActionTokenService(
      Env(privateKey: _otherPrivatePem, publicKey: _otherPublicPem),
    );
    expect(tokens.verify(other.sign(done)), isNull);
  });

  test('rejects a «Готово» without a step and a «Понятно» without a seq', () {
    const noStep = PushActionClaims(
      accountId: 'Uacc',
      action: PushAction.done,
      beaconId: 'Bone',
    );
    const noSeq = PushActionClaims(
      accountId: 'Uacc',
      action: PushAction.ack,
      beaconId: 'Bone',
    );
    expect(tokens.verify(tokens.sign(noStep)), isNull);
    expect(tokens.verify(tokens.sign(noSeq)), isNull);
  });
}

// A throwaway Ed25519 pair, unrelated to the server keys.
const _otherPrivatePem = '''
-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIPdbzee1/3EmP2lN++NlaY20kam2RCh2/Lg4T9FM1oCE
-----END PRIVATE KEY-----''';
const _otherPublicPem = '''
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAdbCnMAAICVFvOnWg5641nIQiSgsN2TEIUO8/0JgrZzU=
-----END PUBLIC KEY-----''';
