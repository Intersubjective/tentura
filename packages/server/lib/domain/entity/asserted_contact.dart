import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/util/email_auth_util.dart';

/// A contact asserted by a credential during auth, with trust evaluation applied.
class AssertedContact {
  const AssertedContact._({
    required this.kind,
    required this.value,
    required this.authoritative,
  });

  final ContactKind kind;

  /// Normalized contact value.
  final String value;

  /// Whether this contact may be used for cross-credential account resolution.
  final bool authoritative;

  /// Normalized, validated email contact. Returns null when invalid or empty.
  static AssertedContact? email({
    required String rawEmail,
    required bool authoritative,
  }) {
    final normalized = normalizeAuthEmail(rawEmail);
    if (!isValidAuthEmailFormat(normalized)) return null;
    return AssertedContact._(
      kind: ContactKind.email,
      value: normalized,
      authoritative: authoritative,
    );
  }

  /// Filters [contacts] to authoritative entries with valid normalized values.
  static List<AssertedContact> authoritativeOnly(
    Iterable<AssertedContact?> contacts,
  ) =>
      contacts
          .whereType<AssertedContact>()
          .where((c) => c.authoritative)
          .toList();
}
