import 'package:tentura_server/domain/entity/verified_contact_entity.dart';

/// Read-only persistence for verified contacts.
abstract class VerifiedContactRepositoryPort {
  /// Returns the account id that owns [kind]/[value], or null when unclaimed.
  Future<String?> getAccountIdByContact({
    required ContactKind kind,
    required String value,
  });

  /// Returns distinct account ids matched by any of [contacts].
  Future<Set<String>> findAccountIdsByContacts(
    Iterable<({ContactKind kind, String value})> contacts,
  );

  /// Newest verified email for [accountId], or null when none is verified.
  /// Email notifications are only sent when this is non-null.
  Future<String?> getPrimaryEmailForAccount(String accountId);
}
