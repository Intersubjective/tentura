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

  static const _maxChildrenPageSize = 50;

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
    await _database
        .into(_database.inviteGenealogy)
        .insert(
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
    final edgeRows = await _fetchAncestorEdgeRows(viewerNodeKey);
    if (edgeRows.isEmpty) {
      return InviteGenealogyGraphEntity(
        viewerNodeKey: viewerNodeKey,
        nodes: [
          await _loadSingleUserNode(userId: userId, nodeKey: viewerNodeKey),
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

    final nodes = await _buildNodes(
      edgeRows: edgeRows,
      seedNodeKeys: {viewerNodeKey},
    );
    return InviteGenealogyGraphEntity(
      viewerNodeKey: viewerNodeKey,
      nodes: nodes,
      edges: edges,
    );
  }

  @override
  Future<InviteGenealogyChildrenPageEntity> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async {
    final clampedLimit = limit.clamp(1, _maxChildrenPageSize);
    final rows = afterCreatedAt != null && afterNodeKey != null
        ? await _database
              .customSelect(
                r'''
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
WHERE ancestor_node_key = $1
  AND (descendant_user_created_at, descendant_node_key) > ($2::text::timestamptz, $3::text)
ORDER BY descendant_user_created_at ASC, descendant_node_key ASC
LIMIT $4
''',
                variables: [
                  Variable<String>(nodeKey),
                  Variable<String>(afterCreatedAt.toUtc().toIso8601String()),
                  Variable<String>(afterNodeKey),
                  Variable<int>(clampedLimit),
                ],
                readsFrom: {_database.inviteGenealogy},
              )
              .get()
        : await _database
              .customSelect(
                r'''
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
WHERE ancestor_node_key = $1
ORDER BY descendant_user_created_at ASC, descendant_node_key ASC
LIMIT $2
''',
                variables: [
                  Variable<String>(nodeKey),
                  Variable<int>(clampedLimit),
                ],
                readsFrom: {_database.inviteGenealogy},
              )
              .get();
    final edgeRows = rows.map(_EdgeRow.fromQueryRow).toList();
    final edges = [
      for (final row in edgeRows)
        InviteGenealogyEdgeEntity(
          ancestorNodeKey: row.ancestorNodeKey,
          descendantNodeKey: row.descendantNodeKey,
          ancestorUserCreatedAt: row.ancestorUserCreatedAt,
          descendantUserCreatedAt: row.descendantUserCreatedAt,
          createdAt: row.createdAt,
        ),
    ];
    final nodes = await _buildNodes(edgeRows: edgeRows, seedNodeKeys: const {});
    return InviteGenealogyChildrenPageEntity(nodes: nodes, edges: edges);
  }

  @override
  Future<InviteGenealogyGraphEntity> fetchLineageBetween({
    required String viewerId,
    required String targetId,
  }) async {
    final viewerNodeKey = await _resolveViewerNodeKey(viewerId);
    final targetNodeKey = await _resolveViewerNodeKey(targetId);

    final viewerEdges = await _fetchAncestorEdgeRows(viewerNodeKey);
    final targetEdges = await _fetchAncestorEdgeRows(targetNodeKey);

    final viewerChain = _ancestorChain(viewerNodeKey, viewerEdges);
    final targetChainSet = _ancestorChain(targetNodeKey, targetEdges).toSet();

    String? commonAncestorNodeKey;
    for (final key in viewerChain) {
      if (targetChainSet.contains(key)) {
        commonAncestorNodeKey = key;
        break;
      }
    }

    // Union both upward chains, deduped by descendant edge (single-parent).
    final edgeByDescendant = <String, _EdgeRow>{};
    for (final row in [...viewerEdges, ...targetEdges]) {
      edgeByDescendant.putIfAbsent(row.descendantNodeKey, () => row);
    }
    final edgeRows = edgeByDescendant.values.toList();

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

    // Seed only from edges: a viewer/target that is itself a root has no
    // ancestor edge, so it is loaded with its real profile by the fallback
    // below instead of appearing as an anonymous seeded node.
    final nodes = await _buildNodes(
      edgeRows: edgeRows,
      seedNodeKeys: const {},
    );

    // Seed users (no ancestor edge) are absent from the edge-derived nodes;
    // load them directly so both endpoints always render.
    final builtKeys = nodes.map((n) => n.nodeKey).toSet();
    final extraNodes = <InviteGenealogyNodeEntity>[];
    if (!builtKeys.contains(viewerNodeKey)) {
      extraNodes.add(
        await _loadSingleUserNode(userId: viewerId, nodeKey: viewerNodeKey),
      );
    }
    if (targetNodeKey != viewerNodeKey && !builtKeys.contains(targetNodeKey)) {
      extraNodes.add(
        await _loadSingleUserNode(userId: targetId, nodeKey: targetNodeKey),
      );
    }

    return InviteGenealogyGraphEntity(
      viewerNodeKey: viewerNodeKey,
      targetNodeKey: targetNodeKey,
      commonAncestorNodeKey: commonAncestorNodeKey,
      nodes: [...nodes, ...extraNodes],
      edges: edges,
    );
  }

  /// Ordered chain of node keys from [startNodeKey] up to its root, following
  /// the single-parent `descendant → ancestor` edges.
  List<String> _ancestorChain(String startNodeKey, List<_EdgeRow> edges) {
    final parentOf = <String, String>{
      for (final row in edges) row.descendantNodeKey: row.ancestorNodeKey,
    };
    final chain = <String>[startNodeKey];
    final seen = <String>{startNodeKey};
    var current = startNodeKey;
    var parent = parentOf[current];
    while (parent != null && seen.add(parent)) {
      chain.add(parent);
      current = parent;
      parent = parentOf[current];
    }
    return chain;
  }

  Future<InviteGenealogyNodeEntity> _loadSingleUserNode({
    required String userId,
    required String nodeKey,
  }) async {
    final userRow = await _database.managers.users
        .filter((e) => e.id(userId))
        .getSingleOrNull();
    final user = userRow == null
        ? null
        : userModelToEntity(
            userRow,
            image: userRow.imageId == null
                ? null
                : await _database.managers.images
                      .filter((e) => e.id(userRow.imageId))
                      .getSingleOrNull(),
          );
    return InviteGenealogyNodeEntity(
      nodeKey: nodeKey,
      user: user,
      userCreatedAt: userRow?.createdAt.dateTime,
    );
  }

  Future<String> _resolveViewerNodeKey(String userId) async {
    final existing = await _database
        .customSelect(
          r'''
SELECT descendant_node_key AS node_key
FROM invite_genealogy
WHERE descendant_user_id = $1
LIMIT 1
''',
          variables: [Variable<String>(userId)],
          readsFrom: {_database.inviteGenealogy},
        )
        .getSingleOrNull();
    if (existing != null) {
      return existing.read<String>('node_key');
    }
    return InviteGenealogyNodeKey.derive(userId: userId, env: _env);
  }

  /// Upward-only walk: every edge from [nodeKey] up to its root.
  Future<List<_EdgeRow>> _fetchAncestorEdgeRows(String nodeKey) async {
    final rows = await _database
        .customSelect(
          r'''
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
  WHERE descendant_node_key = $1
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
)
SELECT * FROM ancestors
''',
          variables: [Variable<String>(nodeKey)],
          readsFrom: {_database.inviteGenealogy},
        )
        .get();
    return rows.map(_EdgeRow.fromQueryRow).toList();
  }

  Future<List<InviteGenealogyNodeEntity>> _buildNodes({
    required List<_EdgeRow> edgeRows,
    required Set<String> seedNodeKeys,
  }) async {
    final nodeKeys = <String>{...seedNodeKeys};
    for (final row in edgeRows) {
      nodeKeys
        ..add(row.ancestorNodeKey)
        ..add(row.descendantNodeKey);
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
      final aCreated =
          a.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bCreated =
          b.userCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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

  factory _EdgeRow.fromQueryRow(QueryRow row) => _EdgeRow(
    ancestorNodeKey: row.read<String>('ancestor_node_key'),
    descendantNodeKey: row.read<String>('descendant_node_key'),
    ancestorUserId: row.readNullable<String>('ancestor_user_id'),
    descendantUserId: row.readNullable<String>('descendant_user_id'),
    ancestorUserCreatedAt: _readTs(row, 'ancestor_user_created_at')!,
    descendantUserCreatedAt: _readTs(row, 'descendant_user_created_at')!,
    ancestorDeletedAt: _readTs(row, 'ancestor_deleted_at'),
    descendantDeletedAt: _readTs(row, 'descendant_deleted_at'),
    createdAt: _readTs(row, 'created_at')!,
  );

  /// Reads a `timestamptz` from a raw `customSelect` row. The postgres driver
  /// returns these as a `DateTime` directly or as an ISO/space-separated text
  /// (the latter when a recursive-CTE `SELECT *` drops the column type oid).
  static DateTime? _readTs(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is PgDateTime) {
      return value.dateTime;
    }
    return DateTime.parse(value.toString());
  }
}
