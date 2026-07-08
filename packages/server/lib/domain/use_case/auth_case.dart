import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:injectable/injectable.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/invite_accepted_notification_intent.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/invite_accepted_notification_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/consts/user_handle_consts.dart';

import '../entity/jwt_entity.dart';
import '../enum.dart';
import '_use_case_base.dart';

@Injectable(order: 2)
final class AuthCase extends UseCaseBase {
  AuthCase(
    this._userRepository,
    this._invitationRepository,
    this._inviteAcceptedNotification, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;
  final InvitationRepositoryPort _invitationRepository;
  final InviteAcceptedNotificationPort _inviteAcceptedNotification;

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
      credentialId: payload[_keyCredentialId] as String? ?? '',
    )..validate();
  }

  //
  //
  Future<JwtEntity> signIn({
    required String authRequestToken,
  }) async {
    final jwt = _verifyAuthRequest(authRequestToken);
    final publicKey =
        (jwt.payload as Map)[AuthRequestIntent.keyPublicKey] as String;
    final user = await _userRepository.getByCredential(
      type: CredentialType.ed25519Device.wire,
      identifier: publicKey,
    );
    // Carry the device credential id in the access token (`cid`) so the
    // session minted from it (`/session/from-bearer`) can attribute its
    // `account_session.credential_id` — an account may hold several device
    // keys, so an account-wide lookup would be ambiguous.
    final credentialId = await _userRepository.findCredentialId(
      type: CredentialType.ed25519Device,
      identifier: publicKey,
    );
    return _issueJwt(user.id, credentialId: credentialId);
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
            final String invitationId => await (() async {
              final invitation =
                  await _invitationRepository.getById(invitationId: invitationId);
              final user = await _userRepository.createInvited(
                invitationId: invitationId,
                publicKey: publicKey,
                displayName: displayName,
                handle: handle,
              );
              if (invitation != null) {
                await _inviteAcceptedNotification.notifyInviteAccepted(
                  InviteAcceptedNotificationIntent(
                    inviterUserId: invitation.issuer.id,
                    accepterUserId: user.id,
                    accepterDisplayName: user.displayName,
                    actionUrl: '/#/shared/view?id=${user.id}',
                  ),
                );
              }
              return user;
            })(),
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

  /// Sign up by accepting an invite whose code is passed explicitly (GraphQL /
  /// native flows), unlike [signUp] which reads the code from the auth-request
  /// JWT payload. Creates the account + its `ed25519_device` credential, befriends the issuer, and forwards the beacon
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
    final invitation =
        await _invitationRepository.getById(invitationId: invitationId);
    final newUser = await _userRepository.createInvited(
      invitationId: invitationId,
      publicKey: publicKey,
      displayName: displayName,
      handle: handle,
    );
    if (invitation != null) {
      await _inviteAcceptedNotification.notifyInviteAccepted(
        InviteAcceptedNotificationIntent(
          inviterUserId: invitation.issuer.id,
          accepterUserId: newUser.id,
          accepterDisplayName: newUser.displayName,
          actionUrl: '/#/shared/view?id=${newUser.id}',
        ),
      );
    }
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

  /// Short-lived API access token (Hasura V1 + V2 + WS). Same shape as signIn.
  JwtEntity issueAccessToken(String accountId) => _issueJwt(accountId);

  JwtEntity _issueJwt(String subject, {String? credentialId}) {
    final jwtId = _uuid.v8();
    final hasCid = credentialId != null && credentialId.isNotEmpty;
    return JwtEntity(
      jti: jwtId,
      sub: subject,
      roles: _roles,
      iss: _issuer,
      exp: env.jwtExpiresIn.inSeconds,
      credentialId: hasCid ? credentialId : '',
      rawToken:
          JWT(
            {
              AuthRequestIntent.keyRoles: _roles.join(','),
              if (hasCid) _keyCredentialId: credentialId,
            },
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

  /// JWT claim carrying the authenticating `account_credential.id`.
  static const _keyCredentialId = 'cid';
}
