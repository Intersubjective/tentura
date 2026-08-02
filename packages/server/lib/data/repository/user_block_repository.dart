import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserBlockRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class UserBlockRepository implements UserBlockRepositoryPort {
  UserBlockRepository(this._db);

  final TenturaDb _db;

  static const _cascadeMaxDepth = 6;
  static const _cascadeMaxRows = 5000;

  @override
  Future<void> block({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) => _db.transaction(() async {
    await _db.customStatement(
      r'''
INSERT INTO public.user_block_intent (
  blocker_id, blocked_id, cascade_mode, cascade_status,
  cascade_snapshot_at, created_at, updated_at
) VALUES ($1, $2, $3, 0, now(), now(), now())
ON CONFLICT (blocker_id, blocked_id) DO UPDATE SET
  cascade_mode = EXCLUDED.cascade_mode,
  cascade_status = 0,
  cascade_snapshot_at = now(),
  updated_at = now()
''',
      [blockerId, blockedId, cascadeMode],
    );
    await _db.customStatement(
      r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ($1, $2, $2)
ON CONFLICT DO NOTHING
''',
      [blockerId, blockedId],
    );
  });

  @override
  Future<void> applyWithdrawal({
    required String blockerId,
    required String blockedId,
  }) async {
    final hasPublishedEdge = await _db
        .customSelect(
          r'''
SELECT EXISTS (
  SELECT 1
  FROM public.user_trust_edge
  WHERE subject = $1
    AND object = $2
    AND prev_sent_weight <> 0
) AS ok
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<bool>('ok'))
        .getSingle();
    if (!hasPublishedEdge) return;

    await _db.customSelect(
      r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
      variables: [
        Variable<String>(blockerId),
        Variable<String>(blockedId),
        const Variable<double>(-1),
      ],
      readsFrom: {},
    ).getSingle();
  }

  @override
  Future<void> unblock({
    required String blockerId,
    required String blockedId,
  }) => _db.transaction(() async {
    final affectedPairs = await _db
        .customSelect(
          r'''
SELECT blocked_id
FROM public.user_block
WHERE blocker_id = $1 AND origin_id = $2
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<String>('blocked_id'))
        .get();

    await _db.customStatement(
      r'''
DELETE FROM public.user_block
WHERE blocker_id = $1 AND origin_id = $2
''',
      [blockerId, blockedId],
    );
    await _db.customStatement(
      r'''
DELETE FROM public.user_block_intent
WHERE blocker_id = $1 AND blocked_id = $2
''',
      [blockerId, blockedId],
    );

    for (final pair in affectedPairs) {
      final hasEdge = await _db
          .customSelect(
            r'''
SELECT EXISTS (
  SELECT 1
  FROM public.user_trust_edge
  WHERE subject = $1 AND object = $2
) AS ok
''',
            variables: [
              Variable<String>(blockerId),
              Variable<String>(pair),
            ],
            readsFrom: {},
          )
          .map((row) => row.read<bool>('ok'))
          .getSingle();
      if (!hasEdge) continue;

      await _db.customSelect(
        r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
        variables: [
          Variable<String>(blockerId),
          Variable<String>(pair),
          const Variable<double>(-1),
        ],
        readsFrom: {},
      ).getSingle();
    }
  });

  @override
  Future<void> promoteToDirect({
    required String blockerId,
    required String blockedId,
  }) => _db.transaction(() async {
    await _db.customStatement(
      r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ($1, $2, $2)
ON CONFLICT DO NOTHING
''',
      [blockerId, blockedId],
    );
    await _db.customStatement(
      r'''
INSERT INTO public.user_block_intent (
  blocker_id, blocked_id, cascade_mode, cascade_status,
  created_at, updated_at
) VALUES ($1, $2, 0, 0, now(), now())
ON CONFLICT (blocker_id, blocked_id) DO UPDATE SET
  cascade_mode = 0,
  updated_at = now()
''',
      [blockerId, blockedId],
    );
  });

  @override
  Future<List<UserBlockIntentEntity>> listIntents(String blockerId) async {
    final rows = await _db.managers.userBlockIntents
        .filter((row) => row.blockerId.id(blockerId))
        .get();
    return rows.map(_intentToEntity).toList(growable: false);
  }

  @override
  Future<List<UserBlockEntity>> listInherited({
    required String blockerId,
    required String originId,
  }) async {
    final rows = await _db.customSelect(
      r'''
SELECT blocker_id, blocked_id, origin_id, created_at
FROM public.user_block
WHERE blocker_id = $1
  AND origin_id = $2
  AND blocked_id <> origin_id
ORDER BY blocked_id
''',
      variables: [
        Variable<String>(blockerId),
        Variable<String>(originId),
      ],
      readsFrom: {_db.userBlocks},
    ).get();
    return rows.map(_blockRowToEntity).toList(growable: false);
  }

  @override
  Future<BlockPreviewEntity> preview({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    final willWithdrawEdge = await _db
        .customSelect(
          r'''
SELECT EXISTS (
  SELECT 1
  FROM public.user_trust_edge
  WHERE subject = $1
    AND object = $2
    AND prev_sent_weight <> 0
) AS ok
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<bool>('ok'))
        .getSingle();

    final openCommitmentCount = await _db
        .customSelect(
          r'''
SELECT COUNT(DISTINCT bc.beacon_id)::int AS c
FROM public.beacon_commitment bc
JOIN public.beacon b ON b.id = bc.beacon_id
WHERE bc.status = 0
  AND ((b.user_id = $1 AND bc.user_id = $2)
    OR (b.user_id = $2 AND bc.user_id = $1))
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<int>('c'))
        .getSingle();

    if (cascadeMode <= 0) {
      return BlockPreviewEntity(
        openCommitmentCount: openCommitmentCount,
        willWithdrawEdge: willWithdrawEdge,
      );
    }

    final candidates = await _db
        .customSelect(
          r'''
SELECT user_id
FROM public.block_cascade_candidates($1, $2, $3, $4, $5)
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
            Variable<int>(cascadeMode),
            const Variable<int>(_cascadeMaxDepth),
            Variable<int>(_cascadeMaxRows + 1),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<String>('user_id'))
        .get();

    final cascadeCapped = candidates.length > _cascadeMaxRows;
    final cascadeCandidateCount = cascadeCapped
        ? _cascadeMaxRows
        : candidates.length;

    return BlockPreviewEntity(
      cascadeCandidateCount: cascadeCandidateCount,
      cascadeCapped: cascadeCapped,
      openCommitmentCount: openCommitmentCount,
      willWithdrawEdge: willWithdrawEdge,
    );
  }

  @override
  Future<bool> isBlockedPair({required String a, required String b}) async {
    final row = await _db
        .customSelect(
          r'SELECT public.block_hides($1, $2) AS hidden',
          variables: [
            Variable<String>(a),
            Variable<String>(b),
          ],
          readsFrom: {},
        )
        .getSingle();
    return row.read<bool>('hidden');
  }

  @override
  Future<Set<String>> hiddenPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async {
    final peers = peerIds.toList(growable: false);
    if (peers.isEmpty) return const {};

    final rows = await _db
        .customSelect(
          r'''
SELECT peer
FROM unnest($2::text[]) AS peer
WHERE public.block_hides($1, peer)
''',
          variables: [
            Variable<String>(viewerId),
            Variable<List<String>>(peers, PgTypes.textArray),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<String>('peer'))
        .get();
    return rows.toSet();
  }

  @override
  Future<List<UserBlockIntentEntity>> claimPendingCascades({
    required int limit,
  }) async {
    final rows = await _db.customSelect(
      r'''
SELECT
  blocker_id,
  blocked_id,
  cascade_mode,
  cascade_status,
  materialized_count,
  created_at
FROM public.user_block_intent
WHERE cascade_status IN (0, 1)
ORDER BY updated_at, blocker_id, blocked_id
LIMIT $1
''',
      variables: [Variable<int>(limit)],
      readsFrom: {_db.userBlockIntents},
    ).get();
    return rows.map(_intentRowToEntity).toList(growable: false);
  }

  @override
  Future<int> materializeCascadeBatch({
    required String blockerId,
    required String blockedId,
    required int limit,
  }) async {
    if (limit <= 0) return 0;

    return _db.transaction(() async {
      final intent = await _db.managers.userBlockIntents
          .filter(
            (row) =>
                row.blockerId.id(blockerId) & row.blockedId.id(blockedId),
          )
          .getSingleOrNull();
      if (intent == null || intent.cascadeMode <= 0) return 0;
      if (intent.cascadeStatus == 2 || intent.cascadeStatus == 3) return 0;

      if (intent.cascadeStatus == 0) {
        await _db.customStatement(
          r'''
UPDATE public.user_block_intent
SET cascade_status = 1,
    cascade_snapshot_at = COALESCE(cascade_snapshot_at, now()),
    updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
          [blockerId, blockedId],
        );
      }

      final candidates = await _db
          .customSelect(
            r'''
SELECT user_id
FROM public.block_cascade_candidates($1, $2, $3, $4, $5)
''',
            variables: [
              Variable<String>(blockerId),
              Variable<String>(blockedId),
              Variable<int>(intent.cascadeMode),
              const Variable<int>(_cascadeMaxDepth),
              Variable<int>(_cascadeMaxRows + 1),
            ],
            readsFrom: {},
          )
          .map((row) => row.read<String>('user_id'))
          .get();

      final capped = candidates.length > _cascadeMaxRows;
      final effectiveCandidates = capped
          ? candidates.take(_cascadeMaxRows).toList(growable: false)
          : candidates;

      final existing = await _db.customSelect(
        r'''
SELECT blocked_id
FROM public.user_block
WHERE blocker_id = $1 AND origin_id = $2
''',
        variables: [
          Variable<String>(blockerId),
          Variable<String>(blockedId),
        ],
        readsFrom: {_db.userBlocks},
      ).map((row) => row.read<String>('blocked_id')).get();
      final existingSet = existing.toSet();

      final pending = [
        for (final userId in effectiveCandidates)
          if (!existingSet.contains(userId)) userId,
      ];
      final batch = pending.take(limit).toList(growable: false);
      if (batch.isEmpty) {
        await _finishCascadeIntent(
          blockerId: blockerId,
          blockedId: blockedId,
          materializedDelta: 0,
          capped: capped,
          done: true,
        );
        return 0;
      }

      for (final userId in batch) {
        await _db.customStatement(
          r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING
''',
          [blockerId, userId, blockedId],
        );
      }

      final done = batch.length == pending.length;
      await _finishCascadeIntent(
        blockerId: blockerId,
        blockedId: blockedId,
        materializedDelta: batch.length,
        capped: capped,
        done: done,
      );
      return batch.length;
    });
  }

  @override
  Future<int> runReleaseSweep({required int limit}) async {
    if (limit <= 0) return 0;

    final deleted = await _db.customSelect(
      r'''
WITH candidates AS (
  SELECT ub.blocker_id, ub.blocked_id, ub.origin_id
  FROM public.user_block ub
  JOIN public.user_block_intent i
    ON i.blocker_id = ub.blocker_id AND i.blocked_id = ub.origin_id
  WHERE i.cascade_mode = 1
    AND ub.blocked_id <> ub.origin_id
    AND (ub.blocker_id, ub.blocked_id, ub.origin_id) > ($1, $2, $3)
  ORDER BY ub.blocker_id, ub.blocked_id, ub.origin_id
  LIMIT $4
),
releasable AS (
  SELECT *
  FROM candidates c
  WHERE NOT public.block_cascade_unattached(
    c.blocker_id, c.origin_id, c.blocked_id
  )
)
DELETE FROM public.user_block ub
USING releasable r
WHERE ub.blocker_id = r.blocker_id
  AND ub.blocked_id = r.blocked_id
  AND ub.origin_id = r.origin_id
RETURNING ub.blocker_id, ub.blocked_id
''',
      variables: [
        const Variable<String>(''),
        const Variable<String>(''),
        const Variable<String>(''),
        Variable(TypedValue(Type.integer, limit)),
      ],
      readsFrom: {_db.userBlocks},
    ).get();

    for (final row in deleted) {
      final blockerId = row.read<String>('blocker_id');
      final blockedId = row.read<String>('blocked_id');
      final hasEdge = await _db
          .customSelect(
            r'''
SELECT EXISTS (
  SELECT 1
  FROM public.user_trust_edge
  WHERE subject = $1 AND object = $2
) AS ok
''',
            variables: [
              Variable<String>(blockerId),
              Variable<String>(blockedId),
            ],
            readsFrom: {},
          )
          .map((r) => r.read<bool>('ok'))
          .getSingle();
      if (!hasEdge) continue;

      await _db.customSelect(
        r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
        variables: [
          Variable<String>(blockerId),
          Variable<String>(blockedId),
          const Variable<double>(-1),
        ],
        readsFrom: {},
      ).getSingle();
    }

    return deleted.length;
  }

  Future<void> _finishCascadeIntent({
    required String blockerId,
    required String blockedId,
    required int materializedDelta,
    required bool capped,
    required bool done,
  }) async {
    if (done) {
      await _db.customStatement(
        r'''
UPDATE public.user_block_intent
SET cascade_status = $3,
    materialized_count = materialized_count + $4,
    updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
        [blockerId, blockedId, capped ? 3 : 2, materializedDelta],
      );
      return;
    }

    await _db.customStatement(
      r'''
UPDATE public.user_block_intent
SET materialized_count = materialized_count + $3,
    updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
      [blockerId, blockedId, materializedDelta],
    );
  }

  static UserBlockEntity _blockRowToEntity(QueryRow row) => UserBlockEntity(
    blockerId: row.read<String>('blocker_id'),
    blockedId: row.read<String>('blocked_id'),
    originId: row.read<String>('origin_id'),
    createdAt: row.read<DateTime>('created_at'),
  );

  static UserBlockIntentEntity _intentToEntity(UserBlockIntent row) =>
      UserBlockIntentEntity(
        blockerId: row.blockerId,
        blockedId: row.blockedId,
        cascadeMode: row.cascadeMode,
        cascadeStatus: row.cascadeStatus,
        materializedCount: row.materializedCount,
        createdAt: row.createdAt.dateTime,
      );

  static UserBlockIntentEntity _intentRowToEntity(QueryRow row) =>
      UserBlockIntentEntity(
        blockerId: row.read<String>('blocker_id'),
        blockedId: row.read<String>('blocked_id'),
        cascadeMode: row.read<int>('cascade_mode'),
        cascadeStatus: row.read<int>('cascade_status'),
        materializedCount: row.read<int>('materialized_count'),
        createdAt: row.read<DateTime>('created_at'),
      );
}
