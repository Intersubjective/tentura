import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';

import '../entity/jwt_entity.dart';
import '../enum.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class AuthCase extends UseCaseBase {
  AuthCase(
    this._userRepository, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;

  late final _roles = {UserRoles.user};

  late final _issuer = env.serverUri.toString();

  ///
  /// Parse and verify JWT issued before and signed with server private key
  ///
  JwtEntity parseAndVerifyJwt({
    required String token,
  }) {
    final jwt = JWT.verify(token, env.publicKey);
    final payload = jwt.payload as Map<String, Object?>;
    final roleList = (payload[AuthRequestIntent.keyRoles] as String? ?? '')
        .split(',');

    // TBD: add all other claims
    return JwtEntity(
      sub: jwt.subject!,
      roles: UserRoles.values.where((e) => roleList.contains(e.name)).toSet(),
    )..validate();
  }

  //
  //
  Future<JwtEntity> signIn({
    required String authRequestToken,
  }) async {
    final jwt = _verifyAuthRequest(authRequestToken);
    final user = await _userRepository.getByPublicKey(
      (jwt.payload as Map)[AuthRequestIntent.keyPublicKey] as String,
    );

    return _issueJwt(user.id);
  }

  //
  //
  Future<JwtEntity> signUp({
    required String authRequestToken,
    required String title,
  }) async {
    final jwt = _verifyAuthRequest(authRequestToken);
    final payload = jwt.payload as Map<String, dynamic>;
    final publicKey = payload[AuthRequestIntent.keyPublicKey]! as String;
    final newUser = env.isNeedInvite
        ? switch (payload[AuthRequestIntentSignUp.keyCode]) {
            final String invitationId => await _userRepository.createInvited(
              invitationId: invitationId,
              publicKey: publicKey,
              title: title,
            ),
            _ => throw const IdWrongException(
              description: 'Invite attribute not found!',
            ),
          }
        : await _userRepository.create(
            publicKey: publicKey,
            title: title,
          );
    return _issueJwt(newUser.id);
  }

  //
  //
  Future<bool> signOut({
    required JwtEntity jwt,
  }) async => true;

  //
  //
  JWT _verifyAuthRequest(String token) {
    final jwtDecoded = JWT.decode(token);

    if (jwtDecoded.header?['alg'] != 'EdDSA') {
      throw JWTInvalidException('Wrong JWT algo!');
    }

    return JWT.verify(
      token,
      EdDSAPublicKey(
        base64Decode(
          base64.normalize(
            (jwtDecoded.payload as Map)[AuthRequestIntent.keyPublicKey]!
                as String,
          ),
        ),
      ),
    );
  }

  //
  //
  JwtEntity _issueJwt(String subject) {
    final jwtId = _uuid.v8();
    return JwtEntity(
      jti: jwtId,
      sub: subject,
      roles: _roles,
      iss: _issuer,
      exp: env.jwtExpiresIn.inSeconds,
      rawToken:
          JWT(
            {AuthRequestIntent.keyRoles: _roles.join(',')},
            jwtId: jwtId,
            subject: subject,
            issuer: _issuer,
          ).sign(
            env.privateKey,
            algorithm: JWTAlgorithm.EdDSA,
            expiresIn: env.jwtExpiresIn,
          ),
    );
  }

  //
  static const _uuid = Uuid();
}
