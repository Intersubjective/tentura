import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/consts.dart';

import '../enum.dart';
import '../exception.dart';

part 'jwt_entity.freezed.dart';
part 'jwt_entity.g.dart';

@freezed
abstract class JwtEntity with _$JwtEntity {
  const factory JwtEntity({
    /// public key
    @Default('') String pk,

    /// JWT id
    @Default('') String jti,

    /// subject id
    @Default('') String sub,

    /// expires in seconds since epoch
    @Default(0) int exp,

    /// not before in seconds since epoch
    @Default(0) int nbf,

    /// Issuer
    @Default('') String iss,

    /// audience
    @Default({}) Set<String> aud,

    /// subject roles
    @Default({UserRoles.anon}) Set<UserRoles> roles,

    /// raw token
    @Default('') String rawToken,
  }) = _JwtEntity;

  factory JwtEntity.fromJson(Map<String, dynamic> json) =>
      _$JwtEntityFromJson(json);

  const JwtEntity._();

  /// Signature algorythm
  String get alg => 'EdDSA';

  /// Token type
  String get typ => 'bearer';

  /// Oauth2 response
  Map<String, Object> get asOauth2Map => {
    'subject': sub,
    'expires_in': exp,
    'token_type': 'bearer',
    'access_token': rawToken,
  };

  String get asJson => jsonEncode(toJson());

  void validate() {
    if (sub.length != kIdLength || !RegExp(r'^U[0-9a-f]+$').hasMatch(sub)) {
      throw IdWrongException(id: sub);
    }
  }
}
