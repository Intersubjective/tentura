import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: VerifiedContactRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class VerifiedContactRepository implements VerifiedContactRepositoryPort {
  const VerifiedContactRepository(this._database);

  final TenturaDb _database;

  @override
  Future<String?> getAccountIdByContact({
    required ContactKind kind,
    required String value,
  }) async {
    final row = await _database.managers.accountVerifiedContacts
        .filter((e) => e.kind(kind.wire) & e.value(value))
        .getSingleOrNull();
    return row?.accountId;
  }

  @override
  Future<Set<String>> findAccountIdsByContacts(
    Iterable<({ContactKind kind, String value})> contacts,
  ) async {
    final ids = <String>{};
    for (final contact in contacts) {
      final accountId = await getAccountIdByContact(
        kind: contact.kind,
        value: contact.value,
      );
      if (accountId != null) {
        ids.add(accountId);
      }
    }
    return ids;
  }
}
