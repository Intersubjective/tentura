import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/user_contact_entity.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserContactRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class UserContactRepository implements UserContactRepositoryPort {
  const UserContactRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> upsert({
    required String viewerId,
    required String subjectId,
    required String contactName,
  }) async {
    await _database
        .into(_database.userContacts)
        .insert(
          UserContactsCompanion.insert(
            viewerId: viewerId,
            subjectId: subjectId,
            contactName: contactName,
          ),
          onConflict: DoUpdate(
            (_) => UserContactsCompanion(
              contactName: Value(contactName),
              updatedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          ),
        );
  }

  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async =>
      await _database.managers.userContacts
          .filter((e) => e.viewerId.id(viewerId) & e.subjectId.id(subjectId))
          .delete() ==
      1;

  @override
  Future<List<UserContactEntity>> fetchAllByViewer({
    required String viewerId,
  }) async {
    final rows = await _database.managers.userContacts
        .filter((e) => e.viewerId.id(viewerId))
        .get();
    return [
      for (final row in rows)
        UserContactEntity(
          viewerId: row.viewerId,
          subjectId: row.subjectId,
          contactName: row.contactName,
          updatedAt: row.updatedAt.dateTime,
        ),
    ];
  }

  @override
  Future<String?> getName({
    required String viewerId,
    required String subjectId,
  }) async {
    final row = await _database.managers.userContacts
        .filter((e) => e.viewerId.id(viewerId) & e.subjectId.id(subjectId))
        .getSingleOrNull();
    return row?.contactName;
  }
}
