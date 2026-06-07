import 'package:tentura_server/utils/id.dart';

/// Kind of verified contact used for identity unification.
enum ContactKind {
  email('email'),
  phone('phone');

  const ContactKind(this.wire);

  final String wire;

  static ContactKind fromWire(String wire) =>
      values.firstWhere((e) => e.wire == wire);
}

/// One verified contact bound to an account (`account_verified_contact` row).
class VerifiedContactEntity {
  const VerifiedContactEntity({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.value,
    required this.lastSource,
    this.verifiedAt,
    this.createdAt,
  });

  static String get newId => generateId('V');

  final String id;
  final String accountId;
  final ContactKind kind;

  /// Normalized email or E.164 phone.
  final String value;

  /// Wire value of the credential type that last asserted this contact.
  final String lastSource;

  final DateTime? verifiedAt;
  final DateTime? createdAt;
}
