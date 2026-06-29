import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';
import '../mapper/user_mapper.dart';

@Injectable(
  as: InviteGenealogyRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class InviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  InviteGenealogyRepository(this._env, this._database);

  final Env _env;
  final TenturaDb _database;

  @override
  Future<void> recordSignupEdge({
    required String ancestorUserId,
    required DateTime ancestorUserCreatedAt,
    required String descendantUserId,
    required DateTime descendantUserCreatedAt,
    required String invitationId,
  }) async {
    final ancestorNodeKey = InviteGenealogyNodeKey.derive(
      userId: ancestorUserId,
      env: _env,
    );
    final descendantNodeKey = InviteGenealogyNodeKey.derive(
      userId: descendantUserId,
      env: _env,
    );
    await _database.into(_database.inviteGenealogy).insert(
      InviteGenealogyCompanion.insert(
        descendantNodeKey: descendantNodeKey,
        ancestorNodeKey: ancestorNodeKey,
        descendantUserId: Value(descendantUserId),
        ancestorUserId: Value(ancestorUserId),
        invitationId: Value(invitationId),
        ancestorUserCreatedAt: PgDateTime(ancestorUserCreatedAt),
        descendantUserCreatedAt: PgDateTime(descendantUserCreatedAt),
      ),
      onConflict: DoNothing(),
    );
  }

  @override
  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String userId,
  }) async {
    final viewerNodeKey = await _resolveViewerNodeKey(userId);
    final edgeRows = await _fetchEdgeRows(viewerNodeKey);
    if (edgeRows.isEmpty) {
      final userRow = await _database.managers.users
          .filter((e) => e.id(userId))
          .getSingleOrNull();
      final viewer = userRow == null
          ? null
          : userModelToEntity(
              userRow,
              image: userRow.imageId == null
                  ? null
                  : await _database.managers.images
                      .filter((e) => e.id(userRow.imageId))
                      .getSingleOrNull(),
            );
      return InviteGenealogyGraphEntity(
        viewerNodeKey: viewerNodeKey,
        nodes: [
          InviteGenealogyNodeEntity(
            nodeKey: viewerNodeKey,
            user: viewer,
            userCreatedAt: userRow?.createdAt.dateTime,
          ),
        ],
        edges: const [],
      );
    }

    final edges = edgeRows
        .map(
          (row) => InviteGenealogyEdgeEntity(
            ancestorNodeKey: row.ancestorNodeKey,
            descendantNodeKey: row.descendantNodeKey,
            ancestorUserCreatedAt: row.ancestorUserCreatedAt,
            descendantUserCreatedAt: row.descendantUserCreatedAt,
            createdAt: row.createdAt,
          ),
        )
        .toList();

    final nodes = await _buildNodes(edgeRows: edgeRows, viewerNodeKey: viewerNodeKey);
    return InviteGenealogyGraphEntity(
      viewerNodeKey: viewerNodeKey,
      nodes: nodes,
      edges: edges,
    );
  }

  Future<String> _resolveViewerNodeKey(String userId) async {
    final existing = await _database.customSelect(
      '''
SELECT descendant_node_key AS node_key
FROM invite_genealogy
WHERE descendant_user_id = @userId
LIMIT 1
''',
      variables: [Variable<String>(userId)],
      readsFrom: {_database.inviteGenealogy},
    ).getSingleOrNull();
    if (existing != null) {
      return existing.read<String>('node_key');
    }
    return InviteGenealogyNodeKey.derive(userId: userId, env: _env);
  }

  Future<List<_EdgeRow>> _fetchEdgeRows(String viewerNodeKey) async {
    final rows = await _database.customSelect(
      '''
WITH RECURSIVE ancestors AS (
  SELECT
    ancestor_node_key,
    descendant_node_key,
    ancestor_user_id,
    descendant_user_id,
    ancestor_user_created_at,
    descendant_user_created_at,
    ancestor_deleted_at,
    descendant_deleted_at,
    created_at
  FROM invite_genealogy
  WHERE descendant_node_key = @viewerNodeKey
  UNION
  SELECT
    ig.ancestor_node_key,
    ig.descendant_node_key,
    ig.ancestor_user_id,
    ig.descendant_user_id,
    ig.ancestor_user_created_at,
    ig.descendant_user_created_at,
    ig.ancestor_deleted_at,
    ig.descendant_deleted_at,
    ig.created_at
  FROM invite_genealogy ig
  INNER JOIN ancestors a ON ig.descendant_node_key = a.ancestor_node_key
),
descendants AS (
  SELECT
    ancestor_node_key,
    descendant_node_key,
    ancestor_user_id,
    descendant_user_id,
    ancestor_user_created_at,
    descendant_user_created_at,
    ancestor_deleted_at,
    descendant_deleted_at,
    created_at
  FROM invite_genealogy
  WHERE ancestor_node_key = @viewerNodeKey
  UNION
  SELECT
    ig.ancestor_node_key,
    ig.descendant_node_key,
    ig.ancestor_user_id,
    ig.descendant_user_id,
    ig.ancestor_user_created_at,
    ig.descendant_user_created_at,
    ig.ancestor_deleted_at,
    ig.descendant_deleted_at,
    ig.created_at
  FROM invite_genealogy ig
  INNER JOIN descendants d ON ig.ancestor_node_key = d.descendant_node_key
)
SELECT * FROM ancestors
UNION
SELECT * FROM descendants
''',
      variables: [Variable<String>(viewerNodeKey)],
      readsFrom: {_database.inviteGenealogy},
    ).get();
    return rows.map(_EdgeRow.fromQueryRow).toList();
  }

  Future<List<InviteGenealogyNodeEntity>> _buildNodes({
    required List<_EdgeRow> edgeRows,
    required String viewerNodeKey,
  }) async {
    final nodeKeys = <String>{viewerNodeKey};
    for (final row in edgeRows) {
      nodeKeys.add(row.ancestorNodeKey);
      nodeKeys.add(row.descendantNodeKey);
    }

    final liveUserIds = <String, String>{};
    final deletedAtByKey = <String, DateTime?>{};
    final createdAtByKey = <String, DateTime>{};

    for (final row in edgeRows) {
      if (row.ancestorUserId != null) {
        liveUserIds[row.ancestorNodeKey] = row.ancestorUserId!;
      } else if (row.ancestorDeletedAt != null) {
        deletedAtByKey[row.ancestorNodeKey] = row.ancestorDeletedAt;
      }
      createdAtByKey.putIfAbsent(
        row.ancestorNodeKey,
        () => row.ancestorUserCreatedAt,
      );

      if (row.descendantUserId != null) {
        liveUserIds[row.descendantNodeKey] = row.descendantUserId!;
      } else if (row.descendantDeletedAt != null) {
        deletedAtByKey[row.descendantNodeKey] = row.descendantDeletedAt;
      }
      createdAtByKey.putIfAbsent(
        row.descendantNodeKey,
        () => row.descendantUserCreatedAt,
      );
    }

    final usersById = await _loadUsersById(liveUserIds.values.toSet());
    final userIdByNodeKey = liveUserIds;

    return [
      for (final nodeKey in nodeKeys)
        InviteGenealogyNodeEntity(
          nodeKey: nodeKey,
          user: userIdByNodeKey[nodeKey] == null
              ? null
              : usersById[userIdByNodeKey[nodeKey]!],
          deletedAt: deletedAtByKey[nodeKey],
          userCreatedAt: createdAtByKey[nodeKey],
        ),
    ]..sort((a, b) {
      final aCreated = a.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bCreated = b.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return aCreated.compareTo(bCreated);
    });
  }

  Future<Map<String, UserEntity>> _loadUsersById(Set<String> userIds) async {
    if (userIds.isEmpty) {
      return {};
    }
    final rows = await _database.managers.users
        .filter((e) => e.id.isIn(userIds.toList()))
        .get();
    final images = <String, Image>{};
    for (final row in rows) {
      final imageId = row.imageId;
      if (imageId != null) {
        final image = await _database.managers.images
            .filter((e) => e.id(imageId))
            .getSingleOrNull();
        if (image != null) {
          images[row.id] = image;
        }
      }
    }
    return {
      for (final row in rows)
        row.id: userModelToEntity(
          row,
          image: images[row.id],
        ),
    };
  }
}

final class _EdgeRow {
  _EdgeRow({
    required this.ancestorNodeKey,
    required this.descendantNodeKey,
    required this.ancestorUserId,
    required this.descendantUserId,
    required this.ancestorUserCreatedAt,
    required this.descendantUserCreatedAt,
    required this.ancestorDeletedAt,
    required this.descendantDeletedAt,
    required this.createdAt,
  });

  final String ancestorNodeKey;
  final String descendantNodeKey;
  final String? ancestorUserId;
  final String? descendantUserId;
  final DateTime ancestorUserCreatedAt;
  final DateTime descendantUserCreatedAt;
  final DateTime? ancestorDeletedAt;
  final DateTime? descendantDeletedAt;
  final DateTime createdAt;

  static _EdgeRow fromQueryRow(QueryRow row) => _EdgeRow(
    ancestorNodeKey: row.read<String>('ancestor_node_key'),
    descendantNodeKey: row.read<String>('descendant_node_key'),
    ancestorUserId: row.readNullable<String>('ancestor_user_id'),
    descendantUserId: row.readNullable<String>('descendant_user_id'),
    ancestorUserCreatedAt: row.read<PgDateTime>('ancestor_user_created_at').dateTime,
    descendantUserCreatedAt:
        row.read<PgDateTime>('descendant_user_created_at').dateTime,
    ancestorDeletedAt: row.readNullable<PgDateTime>('ancestor_deleted_at')?.dateTime,
    descendantDeletedAt:
        row.readNullable<PgDateTime>('descendant_deleted_at')?.dateTime,
    createdAt: row.read<PgDateTime>('created_at').dateTime,
  );
}
