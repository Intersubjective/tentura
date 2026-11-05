import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/person_list_meta_record.dart';
import 'package:tentura_server/domain/port/people_list_meta_repository_port.dart';

import '../database/tentura_db.dart';
import 'constellation_field_repository.dart' show readCustomSelectTimestamptz;
import 'people_list_meta_sql.dart';

@LazySingleton(as: PeopleListMetaRepositoryPort)
class PeopleListMetaRepository implements PeopleListMetaRepositoryPort {
  PeopleListMetaRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<PersonListMetaRecord>> fetchPeopleListMeta({
    required String viewerId,
  }) async {
    if (viewerId.trim().isEmpty) {
      return const [];
    }
    final rows = await _database
        .customSelect(
          kPeopleListMetaSql,
          variables: [Variable.withString(viewerId)],
        )
        .get();
    return [
      for (final row in rows)
        PersonListMetaRecord(
          id: row.read<String>('peer_id'),
          newSince: readCustomSelectTimestamptz(row.data['new_since']),
          newReason: switch (row.readNullable<String>('new_reason')) {
            final String reason => PersonNewReason.values.byName(reason),
            _ => null,
          },
          lastInteractionAt: readCustomSelectTimestamptz(
            row.data['last_interaction_at'],
          ),
        ),
    ];
  }
}
