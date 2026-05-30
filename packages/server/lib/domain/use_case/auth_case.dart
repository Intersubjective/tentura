import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/consts/user_handle_consts.dart';

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
    final user = await _userRepository.getByCredential(
      type: CredentialType.ed25519Device.wire,
      identifier: (jwt.payload as Map)[AuthRequestIntent.keyPublicKey] as String,
    );

    return _issueJwt(user.id);
  }

  //
  //
  Future<JwtEntity> signUp({
    required String authRequestToken,
    required String displayName,
    String? handle,
  }) async {
    final jwt = _verifyAuthRequest(authRequestToken);
    final payload = jwt.payload as Map<String, dynamic>;
    final publicKey = payload[AuthRequestIntent.keyPublicKey]! as String;
    if (handle != null && handle.trim().isNotEmpty) {
      final h = handle.trim().toLowerCase();
      if (!isValidUserHandleFormat(h)) {
        throw const IdWrongException(
          description:
              'Handle must be $kUserHandleMinLength–$kUserHandleMaxLength '
              'characters: lowercase letters, digits, underscore',
        );
      }
    }
    final newUser = env.isNeedInvite
        ? switch (payload[AuthRequestIntentSignUp.keyCode]) {
            final String invitationId => await _userRepository.createInvited(
              invitationId: invitationId,
              publicKey: publicKey,
              displayName: displayName,
              handle: handle,
            ),
            _ => throw const IdWrongException(
              description: 'Invite attribute not found!',
            ),
          }
        : await _userRepository.create(
            publicKey: publicKey,
            displayName: displayName,
            handle: handle,
          );
    return _issueJwt(newUser.id);
  }

  /// Sign up by accepting an invite whose code comes from the request URL
  /// (the landing `accept-as-new` endpoint), unlike [signUp] which reads the
  /// code from the auth-request JWT payload. Creates the account + its
  /// `ed25519_device` credential, befriends the issuer, and forwards the beacon
  /// when the invite carries one (all inside `createInvited`).
  Future<JwtEntity> signUpWithInvite({
    required String authRequestToken,
    required String invitationId,
    required String displayName,
    String? handle,
  }) async {
    final jwt = _verifyAuthRequest(authRequestToken);
    final publicKey =
        (jwt.payload as Map)[AuthRequestIntent.keyPublicKey]! as String;
    if (handle != null && handle.trim().isNotEmpty) {
      final h = handle.trim().toLowerCase();
      if (!isValidUserHandleFormat(h)) {
        throw const IdWrongException(
          description:
              'Handle must be $kUserHandleMinLength–$kUserHandleMaxLength '
              'characters: lowercase letters, digits, underscore',
        );
      }
    }
    final newUser = await _userRepository.createInvited(
      invitationId: invitationId,
      publicKey: publicKey,
      displayName: displayName,
      handle: handle,
    );
    return _issueJwt(newUser.id);
  }

  //
  //
  Future<bool> signOut({
    required JwtEntity jwt,
  }) async => true;

  /// Verify a device auth-request JWT (EdDSA, self-signed by the holder of the
  /// device private key) and return the embedded public key. Used by the
  /// credential-linking path to prove possession of a new device key before
  /// storing it as an `ed25519_device` credential.
  String verifyDeviceAuthRequest(String authRequestToken) =>
      (_verifyAuthRequest(authRequestToken).payload
          as Map)[AuthRequestIntent.keyPublicKey]
      as String;

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
