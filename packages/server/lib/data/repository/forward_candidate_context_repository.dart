import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';

import '../database/tentura_db.dart';
import 'forward_candidate_context_sql.dart';

@LazySingleton(
  as: ForwardCandidateContextRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
final class ForwardCandidateContextRepository
    implements ForwardCandidateContextRepositoryPort {
  ForwardCandidateContextRepository(this._database);

  final TenturaDb _database;

  @override
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async {
    final rows = await _database
        .customSelect(
          kForwardCandidateContextSql,
          variables: [
            Variable.withString(viewerId),
            Variable.withString(candidateId),
            Variable.withString(context),
          ],
        )
        .get();
    if (rows.isEmpty || !rows.first.read<bool>('candidate_eligible')) {
      return const ForwardCandidateGraphSnapshot.unavailable();
    }

    final edges = <ForwardCandidateGraphEdge>[];
    final people = <String, ForwardCandidatePersonProjection>{};
    for (final row in rows) {
      final src = row.readNullable<String>('src');
      final dst = row.readNullable<String>('dst');
      if (src == null || dst == null) continue;
      edges.add(ForwardCandidateGraphEdge(src, dst));
      _readPerson(row, 'src', people);
      _readPerson(row, 'dst', people);
    }
    return ForwardCandidateGraphSnapshot(
      candidateEligible: true,
      edges: edges,
      people: people,
    );
  }
}

void _readPerson(
  QueryRow row,
  String prefix,
  Map<String, ForwardCandidatePersonProjection> people,
) {
  final id = row.readNullable<String>('${prefix}_user_id');
  final displayName = row.readNullable<String>('${prefix}_display_name');
  if (id == null || displayName == null || people.containsKey(id)) return;
  final imageId = row.readNullable<String>('${prefix}_image_id');
  people[id] = ForwardCandidatePersonProjection(
    id: id,
    displayName: displayName,
    image: imageId == null
        ? null
        : ImagePublicRecord(
            id: imageId,
            hash: row.read<String>('${prefix}_image_hash'),
            height: row.read<int>('${prefix}_image_height'),
            width: row.read<int>('${prefix}_image_width'),
            authorId: row.read<String>('${prefix}_image_author_id'),
            createdAt: DateTime.parse(
              row.read<String>('${prefix}_image_created_at'),
            ).toUtc(),
          ),
  );
}
