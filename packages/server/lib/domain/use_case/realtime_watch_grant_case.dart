import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/domain/port/realtime_watch_authorization_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class RealtimeWatchGrantCase extends UseCaseBase {
  RealtimeWatchGrantCase(
    this._authorizationPort, {
    required super.env,
    required super.logger,
  });

  final RealtimeWatchAuthorizationPort _authorizationPort;

  static const protocolVersion = 1;
  static const audience = 'tentura:realtime-watch';
  static const _purpose = 'realtime_watch';
  static const _uuid = Uuid();

  Future<RealtimeWatchGrant> issue({
    required String viewerId,
    required RealtimeWatchDescriptor descriptor,
  }) async {
    _validateDescriptor(descriptor);
    final authorized = await _authorizationPort.authorizeSubjects(
      viewerId: viewerId,
      descriptor: descriptor,
    );
    final subjectIds = descriptor.requestedSubjectIds
        .where(authorized.contains)
        .toSet();
    _validateSubjects(subjectIds);

    final now = DateTime.timestamp().toUtc();
    final expiresAt = now.add(env.realtimeWatchGrantTtl);
    final tokenId = _uuid.v8();
    final token =
        JWT(
          {
            'purpose': _purpose,
            'version': protocolVersion,
            'viewer': viewerId,
            'scope': descriptor.scope.name,
            'subjects': subjectIds.toList()..sort(),
            'projection': _projectionClaims(descriptor),
          },
          subject: viewerId,
          issuer: env.publicOrigin,
          audience: Audience.one(audience),
          jwtId: tokenId,
        ).sign(
          env.privateKey,
          algorithm: JWTAlgorithm.EdDSA,
          expiresIn: env.realtimeWatchGrantTtl,
        );
    if (utf8.encode(token).length > env.realtimeWatchMaxBytes) {
      throw const FormatException('Realtime watch grant exceeds byte limit');
    }
    return RealtimeWatchGrant(
      token: token,
      scope: descriptor.scope,
      authorizedSubjectIds: subjectIds,
      expiresAt: expiresAt,
    );
  }

  /// Returns null for every invalid, forged, expired, or cross-account grant.
  RealtimeWatchGrantClaims? verify({
    required String token,
    required String accountId,
    RealtimeWatchScope? expectedScope,
  }) {
    if (token.isEmpty ||
        utf8.encode(token).length > env.realtimeWatchMaxBytes) {
      return null;
    }
    try {
      final jwt = JWT.verify(
        token,
        env.publicKey,
        issuer: env.publicOrigin,
        audience: Audience.one(audience),
      );
      final payload = (jwt.payload as Map).cast<String, dynamic>();
      final scope = RealtimeWatchScope.fromWire(payload['scope']);
      final rawSubjects = payload['subjects'];
      final viewer = payload['viewer'];
      final version = payload['version'];
      final expiresSeconds = payload['exp'];
      if (payload['purpose'] != _purpose ||
          version != protocolVersion ||
          viewer != accountId ||
          jwt.subject != accountId ||
          scope == null ||
          (expectedScope != null && scope != expectedScope) ||
          rawSubjects is! List ||
          expiresSeconds is! int ||
          jwt.jwtId == null ||
          jwt.jwtId!.isEmpty) {
        return null;
      }
      final subjectIds = rawSubjects.whereType<String>().toSet();
      if (subjectIds.length != rawSubjects.length) return null;
      _validateSubjects(subjectIds);
      return RealtimeWatchGrantClaims(
        viewerId: accountId,
        scope: scope,
        subjectIds: subjectIds,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          expiresSeconds * 1000,
          isUtc: true,
        ),
        tokenId: jwt.jwtId!,
      );
    } on Object {
      return null;
    }
  }

  void _validateDescriptor(RealtimeWatchDescriptor descriptor) {
    _validateSubjects(descriptor.requestedSubjectIds);
    switch (descriptor.scope) {
      case RealtimeWatchScope.graph:
        if (!_validProjectionId(descriptor.focusId) ||
            descriptor.context == null ||
            descriptor.positiveOnly == null ||
            descriptor.profileId != null ||
            descriptor.beaconId != null) {
          throw const FormatException('Invalid graph watch descriptor');
        }
      case RealtimeWatchScope.profile:
        if (!_validUserId(descriptor.profileId) ||
            !descriptor.requestedSubjectIds.contains(descriptor.profileId) ||
            descriptor.focusId != null ||
            descriptor.context != null ||
            descriptor.positiveOnly != null ||
            descriptor.beaconId != null) {
          throw const FormatException('Invalid profile watch descriptor');
        }
      case RealtimeWatchScope.people:
        if (!_validBeaconId(descriptor.beaconId) ||
            descriptor.focusId != null ||
            descriptor.context != null ||
            descriptor.positiveOnly != null ||
            descriptor.profileId != null) {
          throw const FormatException('Invalid people watch descriptor');
        }
    }
  }

  void _validateSubjects(Set<String> subjectIds) {
    if (subjectIds.length > env.realtimeWatchMaxSubjects ||
        subjectIds.any((id) => !_validUserId(id)) ||
        utf8.encode((subjectIds.toList()..sort()).join(',')).length >
            env.realtimeWatchMaxBytes) {
      throw const FormatException('Invalid realtime watch subjects');
    }
  }

  static bool _validProjectionId(String? id) =>
      _validUserId(id) || _validBeaconId(id);

  static bool _validUserId(String? id) =>
      id != null && id.startsWith('U') && id.length > 1 && id.length <= 128;

  static bool _validBeaconId(String? id) =>
      id != null && id.startsWith('B') && id.length > 1 && id.length <= 128;

  static Map<String, Object?> _projectionClaims(
    RealtimeWatchDescriptor descriptor,
  ) => switch (descriptor.scope) {
    RealtimeWatchScope.graph => {
      'focus': descriptor.focusId,
      'context': descriptor.context,
      'positive_only': descriptor.positiveOnly,
    },
    RealtimeWatchScope.profile => {'profile_id': descriptor.profileId},
    RealtimeWatchScope.people => {'beacon_id': descriptor.beaconId},
  };
}
