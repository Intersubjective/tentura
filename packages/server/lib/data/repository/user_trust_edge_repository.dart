import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/trust/trust_edge.dart';
import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/trust/dirichlet_counts.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';
import 'package:tentura_server/env.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserTrustEdgeRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class UserTrustEdgeRepository implements UserTrustEdgeRepositoryPort {
  UserTrustEdgeRepository(
    this._db,
    this._meritrank,
    this._env,
  );

  final TenturaDb _db;
  final MeritrankRepositoryPort _meritrank;
  final Env _env;

  Duration get _halfLife => _env.trustEdgeHalfLife;

  double get _epsilon => _env.trustEdgeEpsilon;

  @override
  Future<void> applyEvidence(TrustEvidenceBatch batch) =>
      _db.transaction(() => _applyCore(batch));

  @override
  Future<void> applyEvidenceInTransaction(TrustEvidenceBatch batch) =>
      _applyCore(batch);

  @override
  Future<void> setVoteAmountAndApplyEvidence({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) => _db.transaction(
    () => _setVoteAmountCore(
      subjectUserId: subjectUserId,
      objectUserId: objectUserId,
      newAmount: newAmount,
    ),
  );

  @override
  Future<void> setVoteAmountAndApplyEvidenceInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) => _setVoteAmountCore(
    subjectUserId: subjectUserId,
    objectUserId: objectUserId,
    newAmount: newAmount,
  );

  @override
  Future<void> forceRefreshStar(String sourceUserId) => _db.transaction(() async {
    await _acquireSourceLock(sourceUserId);
    final at = DateTime.timestamp();
    final edges = await _loadStar(sourceUserId);
    for (final edge in edges) {
      await _refreshEdge(
        edge: edge,
        at: at,
        bypassEpsilon: true,
      );
    }
  });

  @override
  Future<void> forceRefreshAll() async {
    final sources = await _db.customSelect(
      'SELECT DISTINCT subject FROM user_trust_edge',
    ).map((r) => r.read<String>('subject')).get();
    for (final source in sources) {
      await _db.transaction(() async {
        await _acquireSourceLock(source);
        final at = DateTime.timestamp();
        final edges = await _loadStar(source);
        for (final edge in edges) {
          await _recomputeAndPersistEdge(edge: edge, at: at);
        }
      });
    }
    await _meritrank.reset();
    await _meritrank.init();
  }

  @override
  Future<void> cutoverBackfillIfNeeded() async {
    final trustCount = await _db.customSelect(
      'SELECT count(*)::int AS c FROM user_trust_edge',
    ).map((r) => r.read<int>('c')).getSingle();
    if (trustCount > 0) return;

    final votes = await _db.customSelect(
      'SELECT subject, object, amount FROM vote_user WHERE amount <> 0',
    ).get();
    if (votes.isEmpty) return;

    final now = DateTime.timestamp();
    await _db.transaction(() async {
      for (final vote in votes) {
        final amount = vote.read<int>('amount');
        final bin = voteAmountToBin(amount);
        if (bin == null) continue;
        final counts = DirichletCounts.zero.withAdded(bin, kTrustVoteEvidenceCount);
        final weight = expectedWeight(counts);
        await _db.into(_db.userTrustEdges).insert(
          UserTrustEdgesCompanion.insert(
            subject: vote.read<String>('subject'),
            object: vote.read<String>('object'),
            cVeryBad: Value(counts.veryBad),
            cBad: Value(counts.bad),
            cNoEffect: Value(counts.noEffect),
            cGood: Value(counts.good),
            cVeryGood: Value(counts.veryGood),
            lastDecayAt: PgDateTime(now),
            prevSentWeight: Value(weight),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });

    await _meritrank.reset();
    await _meritrank.init();
  }

  Future<void> _setVoteAmountCore({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) async {
    final existing = await _db.managers.voteUsers
        .filter(
          (v) =>
              v.subject.id(subjectUserId) & v.object.id(objectUserId),
        )
        .getSingleOrNull();
    final previousAmount = existing?.amount ?? 0;
    if (previousAmount == newAmount) return;

    if (existing == null) {
      await _db.managers.voteUsers.create(
        (o) => o(
          subject: subjectUserId,
          object: objectUserId,
          amount: newAmount,
        ),
      );
    } else {
      await _db.managers.voteUsers
          .filter(
            (v) =>
                v.subject.id(subjectUserId) & v.object.id(objectUserId),
          )
          .update((o) => o(amount: Value(newAmount)));
    }

    final bin = voteAmountToBin(newAmount);
    if (bin == null) return;

    await _applyCore(
      TrustEvidenceBatch(
        sourceUserId: subjectUserId,
        at: DateTime.timestamp(),
        items: [
          TrustEvidence(
            targetUserId: objectUserId,
            bin: bin,
            count: kTrustVoteEvidenceCount,
          ),
        ],
      ),
    );
  }

  Future<void> _applyCore(TrustEvidenceBatch batch) async {
    if (batch.items.isEmpty) return;
    await _acquireSourceLock(batch.sourceUserId);
    final edges = await _loadStar(batch.sourceUserId);
    final edgeByObject = {for (final e in edges) e.object: e};
    final at = batch.at;

    for (final edge in edges) {
      final decayed = _decayEdge(edge, at);
      edgeByObject[edge.object] = decayed;
    }

    for (final item in batch.items) {
      final current = edgeByObject[item.targetUserId] ??
          TrustEdge(
            subject: batch.sourceUserId,
            object: item.targetUserId,
            counts: DirichletCounts.zero,
            lastDecayAt: at,
            prevSentWeight: 0,
          );
      final updated = current.copyWith(
        counts: current.counts.withAdded(item.bin, item.count),
        lastDecayAt: at,
      );
      edgeByObject[item.targetUserId] = updated;
    }

    for (final edge in edgeByObject.values) {
      await _refreshEdge(edge: edge, at: at, bypassEpsilon: false);
    }
  }

  Future<void> _recomputeAndPersistEdge({
    required TrustEdge edge,
    required DateTime at,
  }) async {
    final decayed = _decayEdge(edge, at);
    final weight = expectedWeight(decayed.counts);
    await _persistEdge(
      decayed.copyWith(
        prevSentWeight: weight,
        lastDecayAt: at,
      ),
    );
  }

  Future<void> _refreshEdge({
    required TrustEdge edge,
    required DateTime at,
    required bool bypassEpsilon,
  }) async {
    final weight = expectedWeight(edge.counts);
    final shouldPush =
        bypassEpsilon || (weight - edge.prevSentWeight).abs() > _epsilon;
    if (shouldPush) {
      await _meritrank.putEdge(
        nodeA: edge.subject,
        nodeB: edge.object,
        weight: weight,
      );
    }
    await _persistEdge(
      edge.copyWith(
        prevSentWeight: shouldPush ? weight : edge.prevSentWeight,
        lastDecayAt: at,
      ),
    );
  }

  TrustEdge _decayEdge(TrustEdge edge, DateTime at) {
    final elapsed = at.difference(edge.lastDecayAt);
    return edge.copyWith(
      counts: decayCounts(
        counts: edge.counts,
        elapsed: elapsed,
        halfLife: _halfLife,
      ),
      lastDecayAt: at,
    );
  }

  Future<void> _acquireSourceLock(String sourceUserId) => _db.customSelect(
    r'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
    variables: [Variable<String>(sourceUserId)],
  ).getSingle();

  Future<List<TrustEdge>> _loadStar(String sourceUserId) async {
    final rows = await _db.managers.userTrustEdges
        .filter((e) => e.subject.id(sourceUserId))
        .get();
    return rows.map(_rowToEntity).toList();
  }

  Future<void> _persistEdge(TrustEdge edge) => _db.into(_db.userTrustEdges).insert(
    UserTrustEdgesCompanion.insert(
      subject: edge.subject,
      object: edge.object,
      cVeryBad: Value(edge.counts.veryBad),
      cBad: Value(edge.counts.bad),
      cNoEffect: Value(edge.counts.noEffect),
      cGood: Value(edge.counts.good),
      cVeryGood: Value(edge.counts.veryGood),
      lastDecayAt: PgDateTime(edge.lastDecayAt),
      prevSentWeight: Value(edge.prevSentWeight),
      updatedAt: Value(PgDateTime(DateTime.timestamp())),
    ),
    mode: InsertMode.insertOrReplace,
  );

  TrustEdge _rowToEntity(UserTrustEdge row) => TrustEdge(
    subject: row.subject,
    object: row.object,
    counts: DirichletCounts(
      veryBad: row.cVeryBad,
      bad: row.cBad,
      noEffect: row.cNoEffect,
      good: row.cGood,
      veryGood: row.cVeryGood,
    ),
    lastDecayAt: row.lastDecayAt.dateTime,
    prevSentWeight: row.prevSentWeight,
  );
}
