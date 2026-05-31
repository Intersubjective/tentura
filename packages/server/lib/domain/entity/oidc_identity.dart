import 'package:freezed_annotation/freezed_annotation.dart';

part 'oidc_identity.freezed.dart';

/// Verified OIDC subject claims (anti-corruption output of the OIDC provider port).
@freezed
abstract class OidcIdentity with _$OidcIdentity {
  const factory OidcIdentity({
    required String sub,
    @Default('') String email,
    @Default('') String name,
    Map<String, Object?>? publicData,
  }) = _OidcIdentity;

  const OidcIdentity._();

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    final e = email.trim();
    if (e.isNotEmpty) {
      final at = e.indexOf('@');
      return at > 0 ? e.substring(0, at) : e;
    }
    return 'User';
  }
}
