import 'package:injectable/injectable.dart';

import 'package:tentura/data/database/database.dart';
import 'package:tentura/data/service/remote_api_service.dart';

import '../gql/_g/contact_delete.req.gql.dart';
import '../gql/_g/contact_set.req.gql.dart';
import '../gql/_g/contacts_fetch_mine.req.gql.dart';

/// Subjective profiles: remote contact CRUD + per-account Drift cache.
/// The cache makes contact names render offline; mutations are online-only.
@Singleton(env: [Environment.dev, Environment.prod])
class ContactsRepository {
  ContactsRepository(
    this._remoteApiService,
    this._database,
  );

  final RemoteApiService _remoteApiService;

  final Database _database;

  /// The viewer's full contact map from the server: subjectId -> contactName.
  Future<Map<String, String>> fetchMine() => _remoteApiService
      .request(GMyContactsReq())
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then(
        (r) => {
          for (final c in r.dataOrThrow(label: _label).myContacts)
            c.subjectId: c.contactName,
        },
      );

  Future<void> setContact({
    required String subjectId,
    required String contactName,
  }) => _remoteApiService
      .request(
        GContactSetReq(
          (r) => r
            ..vars.subjectUserId = subjectId
            ..vars.contactName = contactName,
        ),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  Future<void> deleteContact({required String subjectId}) => _remoteApiService
      .request(
        GContactDeleteReq((r) => r..vars.subjectUserId = subjectId),
      )
      .firstWhere((e) => e.dataSource == DataSource.Link)
      .then((r) => r.dataOrThrow(label: _label));

  //
  // Drift cache, keyed per account (one device can hold several).
  //

  Future<Map<String, String>> getCached({required String accountId}) async {
    final rows = await _database.managers.contacts
        .filter((e) => e.accountId.equals(accountId))
        .get();
    return {for (final row in rows) row.subjectId: row.contactName};
  }

  Future<void> replaceCache({
    required String accountId,
    required Map<String, String> names,
  }) => _database.transaction(() async {
    await _database.managers.contacts
        .filter((e) => e.accountId.equals(accountId))
        .delete();
    if (names.isNotEmpty) {
      await _database.managers.contacts.bulkCreate(
        (o) => [
          for (final entry in names.entries)
            o(
              accountId: accountId,
              subjectId: entry.key,
              contactName: entry.value,
            ),
        ],
      );
    }
  });

  Future<void> putCached({
    required String accountId,
    required String subjectId,
    required String contactName,
  }) => _database.managers.contacts.create(
    (o) => o(
      accountId: accountId,
      subjectId: subjectId,
      contactName: contactName,
    ),
    mode: InsertMode.insertOrReplace,
  );

  Future<void> removeCached({
    required String accountId,
    required String subjectId,
  }) => _database.managers.contacts
      .filter(
        (e) => e.accountId.equals(accountId) & e.subjectId.equals(subjectId),
      )
      .delete();

  static const _label = 'Contacts';
}
