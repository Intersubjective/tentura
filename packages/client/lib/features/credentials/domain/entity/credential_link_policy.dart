import 'credential_entity.dart';
import 'credential_types.dart';

/// Which credential types may be linked given what is already on the account.
abstract final class CredentialLinkPolicy {
  static bool canLink(String type, Iterable<CredentialEntity> linked) =>
      switch (type) {
        CredentialTypes.oidcGoogle || CredentialTypes.emailOtp =>
          !linked.hasType(type),
        CredentialTypes.ed25519Device => true,
        _ => false,
      };
}
