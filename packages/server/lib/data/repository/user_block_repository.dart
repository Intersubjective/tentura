import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/entity/user_block_entity.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserBlockRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class UserBlockRepository implements UserBlockRepositoryPort {
  UserBlockRepository(
    this._env,
    this._db, {
    WitnessWindowPort? witnessWindow,
  }) : _witnessWindow = witnessWindow;

  final Env _env;
  final TenturaDb _db;
  final WitnessWindowPort? _witnessWindow;

  int get _cascadeMaxDepth => _env.blockCascadeMaxDepth;
  int get _cascadeMaxRows => _env.blockCascadeMaxRows;

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
    await _invalidateWitnessWindows(blockerId, blockedId);
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
  Future<int> countRecentByBlocker({
    required String blockerId,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final row = await _db
        .customSelect(
          r'''
SELECT COUNT(*)::int AS c
FROM public.user_block_intent
WHERE blocker_id = $1 AND updated_at >= $2
''',
          variables: [
            Variable<String>(blockerId),
            Variable(TypedValue(Type.timestampTz, since)),
          ],
          readsFrom: {},
        )
        .getSingle();
    return row.read<int>('c');
  }

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
FROM public.beacon_help_offer bc
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
FROM public.block_cascade_candidates($1, $2, $3::smallint, $4::integer, $5::integer)
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
            Variable<int>(cascadeMode),
            Variable<int>(_cascadeMaxDepth),
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
    final rows = await _db.managers.userBlockIntents
        .filter(
          (row) =>
              row.cascadeStatus.equals(0) | row.cascadeStatus.equals(1),
        )
        .get();
    rows.sort((a, b) {
      final byUpdated = a.updatedAt.dateTime.compareTo(b.updatedAt.dateTime);
      if (byUpdated != 0) return byUpdated;
      final byBlocker = a.blockerId.compareTo(b.blockerId);
      if (byBlocker != 0) return byBlocker;
      return a.blockedId.compareTo(b.blockedId);
    });
    return rows
        .take(limit)
        .map(_intentToEntity)
        .toList(growable: false);
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
FROM public.block_cascade_candidates($1, $2, $3::smallint, $4::integer, $5::integer)
''',
            variables: [
              Variable<String>(blockerId),
              Variable<String>(blockedId),
              Variable<int>(intent.cascadeMode),
              Variable<int>(_cascadeMaxDepth),
              Variable<int>(_cascadeMaxRows + 1),
            ],
            readsFrom: {},
          )
          .map((row) => row.read<String>('user_id'))
          .get();

      final rowCapped = candidates.length > _cascadeMaxRows;
      final effectiveCandidates = rowCapped
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
        final caughtUp = await catchUpCascadeIntent(
          blockerId: blockerId,
          blockedId: blockedId,
        );
        if (caughtUp > 0) {
          await _db.customStatement(
            r'''
UPDATE public.user_block_intent
SET materialized_count = materialized_count + $3,
    updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
            [blockerId, blockedId, caughtUp],
          );
          return caughtUp;
        }

        final capped =
            rowCapped ||
            await _isDepthCapped(
              blockerId: blockerId,
              blockedId: blockedId,
              cascadeMode: intent.cascadeMode,
            );
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
        await applyWithdrawal(blockerId: blockerId, blockedId: userId);
      }

      final done = batch.length == pending.length;
      if (done) {
        final caughtUp = await catchUpCascadeIntent(
          blockerId: blockerId,
          blockedId: blockedId,
        );
        if (caughtUp > 0) {
          await _db.customStatement(
            r'''
UPDATE public.user_block_intent
SET materialized_count = materialized_count + $3,
    updated_at = now()
WHERE blocker_id = $1 AND blocked_id = $2
''',
            [blockerId, blockedId, caughtUp + batch.length],
          );
          return caughtUp + batch.length;
        }

        final capped =
            rowCapped ||
            await _isDepthCapped(
              blockerId: blockerId,
              blockedId: blockedId,
              cascadeMode: intent.cascadeMode,
            );
        await _finishCascadeIntent(
          blockerId: blockerId,
          blockedId: blockedId,
          materializedDelta: batch.length,
          capped: capped,
          done: true,
        );
        return batch.length;
      }

      await _finishCascadeIntent(
        blockerId: blockerId,
        blockedId: blockedId,
        materializedDelta: batch.length,
        capped: false,
        done: false,
      );
      return batch.length;
    });
  }

  @override
  Future<int> catchUpCascadeIntent({
    required String blockerId,
    required String blockedId,
  }) async {
    final intent = await _db.managers.userBlockIntents
        .filter(
          (row) =>
              row.blockerId.id(blockerId) & row.blockedId.id(blockedId),
        )
        .getSingleOrNull();
    final snapshotAt = intent?.cascadeSnapshotAt?.dateTime;
    if (snapshotAt == null) return 0;

    final inserted = await _db
        .customSelect(
          r'''
WITH inserted AS (
  INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
  SELECT $1, g.descendant_user_id, $2
  FROM public.invite_genealogy g
  WHERE g.created_at > $3::timestamptz
    AND g.descendant_user_id IS NOT NULL
    AND g.ancestor_user_id IS NOT NULL
    AND g.descendant_user_id <> $1
    AND EXISTS (
      SELECT 1
      FROM public.user_block ub
      WHERE ub.blocker_id = $1
        AND ub.blocked_id = g.ancestor_user_id
        AND ub.origin_id = $2
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_block existing
      WHERE existing.blocker_id = $1
        AND existing.blocked_id = g.descendant_user_id
        AND existing.origin_id = $2
    )
  ON CONFLICT DO NOTHING
  RETURNING blocked_id
)
SELECT blocked_id FROM inserted
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
            Variable<String>(snapshotAt.toUtc().toIso8601String()),
          ],
          readsFrom: {_db.userBlocks, _db.inviteGenealogy},
        )
        .map((row) => row.read<String>('blocked_id'))
        .get();

    for (final userId in inserted) {
      await applyWithdrawal(blockerId: blockerId, blockedId: userId);
    }
    return inserted.length;
  }

  @override
  Future<BlockReleaseSweepBatch> runReleaseSweep({
    required int limit,
    BlockReleaseSweepCursor? afterCursor,
  }) async {
    if (limit <= 0) {
      return (
        deletedCount: 0,
        lastExaminedCandidate: null,
        reachedTail: true,
      );
    }

    final cursorBlocker = afterCursor?.blockerId ?? '';
    final cursorBlocked = afterCursor?.blockedId ?? '';
    final cursorOrigin = afterCursor?.originId ?? '';

    return _db.transaction(() async {
      final candidates = await _db.customSelect(
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
)
SELECT
  c.blocker_id,
  c.blocked_id,
  c.origin_id,
  public.block_cascade_unattached(
    c.blocker_id, c.origin_id, c.blocked_id
  ) AS unattached
FROM candidates c
''',
        variables: [
          Variable<String>(cursorBlocker),
          Variable<String>(cursorBlocked),
          Variable<String>(cursorOrigin),
          Variable(TypedValue(Type.integer, limit)),
        ],
        readsFrom: {_db.userBlocks},
      ).get();

      if (candidates.isEmpty) {
        return (
          deletedCount: 0,
          lastExaminedCandidate: null,
          reachedTail: true,
        );
      }

      final lastRow = candidates.last;
      final lastExaminedCandidate = (
        blockerId: lastRow.read<String>('blocker_id'),
        blockedId: lastRow.read<String>('blocked_id'),
        originId: lastRow.read<String>('origin_id'),
      );
      final reachedTail = candidates.length < limit;

      final releasable = candidates
          .where((row) => !row.read<bool>('unattached'))
          .toList(growable: false);
      if (releasable.isEmpty) {
        return (
          deletedCount: 0,
          lastExaminedCandidate: lastExaminedCandidate,
          reachedTail: reachedTail,
        );
      }

      final deleted = await _db.customSelect(
        r'''
DELETE FROM public.user_block ub
USING (
  SELECT *
  FROM unnest($1::text[], $2::text[], $3::text[])
    AS t(blocker_id, blocked_id, origin_id)
) r
WHERE ub.blocker_id = r.blocker_id
  AND ub.blocked_id = r.blocked_id
  AND ub.origin_id = r.origin_id
RETURNING ub.blocker_id, ub.blocked_id
''',
        variables: [
          Variable<List<String>>(
            releasable.map((r) => r.read<String>('blocker_id')).toList(),
            PgTypes.textArray,
          ),
          Variable<List<String>>(
            releasable.map((r) => r.read<String>('blocked_id')).toList(),
            PgTypes.textArray,
          ),
          Variable<List<String>>(
            releasable.map((r) => r.read<String>('origin_id')).toList(),
            PgTypes.textArray,
          ),
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
        await _invalidateWitnessWindows(blockerId, blockedId);
      }

      return (
        deletedCount: deleted.length,
        lastExaminedCandidate: lastExaminedCandidate,
        reachedTail: reachedTail,
      );
    });
  }

  Future<bool> _isDepthCapped({
    required String blockerId,
    required String blockedId,
    required int cascadeMode,
  }) async {
    final shallow = await _db
        .customSelect(
          r'''
SELECT user_id
FROM public.block_cascade_candidates($1, $2, $3::smallint, $4::integer, $5::integer)
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
            Variable<int>(cascadeMode),
            Variable<int>(_cascadeMaxDepth),
            Variable<int>(_cascadeMaxRows + 1),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<String>('user_id'))
        .get();
    final deep = await _db
        .customSelect(
          r'''
SELECT user_id
FROM public.block_cascade_candidates($1, $2, $3::smallint, $4::integer, $5::integer)
''',
          variables: [
            Variable<String>(blockerId),
            Variable<String>(blockedId),
            Variable<int>(cascadeMode),
            Variable<int>(_cascadeMaxDepth + 1),
            Variable<int>(_cascadeMaxRows + 1),
          ],
          readsFrom: {},
        )
        .map((row) => row.read<String>('user_id'))
        .get();
    return deep.length > shallow.length;
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

  Future<void> _invalidateWitnessWindows(
    String blockerId,
    String blockedId,
  ) async {
    final witnessWindow = _witnessWindow;
    if (witnessWindow == null) return;
    await witnessWindow.invalidateFor(userId: blockerId);
    await witnessWindow.invalidateFor(userId: blockedId);
  }
}
