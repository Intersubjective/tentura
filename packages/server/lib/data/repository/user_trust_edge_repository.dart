import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
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

  double get _halfLifeSeconds => _env.trustEdgeHalfLife.inSeconds.toDouble();

  double get _epsilon => _env.trustEdgeEpsilon;

  @override
  Future<void> applyEvidence(TrustEvidenceBatch batch) async {
    for (final item in batch.items) {
      try {
        await _applyEvidenceItem(
          subjectUserId: batch.sourceUserId,
          item: item,
        );
      } catch (_) {
        // Best-effort per edge.
      }
    }
  }

  @override
  Future<void> applyEvidenceInTransaction(TrustEvidenceBatch batch) async {
    var index = 0;
    for (final item in batch.items) {
      final savepoint = 'trust_ev_$index';
      index += 1;
      await _db.customStatement('SAVEPOINT $savepoint');
      try {
        await _applyEvidenceItem(
          subjectUserId: batch.sourceUserId,
          item: item,
        );
      } catch (_) {
        await _db.customStatement('ROLLBACK TO SAVEPOINT $savepoint');
      } finally {
        await _db.customStatement('RELEASE SAVEPOINT $savepoint');
      }
    }
  }

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
  Future<bool> setVoteAmountAndDetectMutualFormationInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) async {
    final pair = [subjectUserId, objectUserId]..sort();
    await _db.customStatement(
      r'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      ['${pair.first}|${pair.last}'],
    );
    final previousAmount = await _voteAmount(
      subjectUserId: subjectUserId,
      objectUserId: objectUserId,
    );
    final reverseAmount = await _voteAmount(
      subjectUserId: objectUserId,
      objectUserId: subjectUserId,
    );
    await _setVoteAmountCore(
      subjectUserId: subjectUserId,
      objectUserId: objectUserId,
      newAmount: newAmount,
    );
    return previousAmount <= 0 && newAmount > 0 && reverseAmount > 0;
  }

  @override
  Future<void> forceRefreshStar(String sourceUserId) async {
    await _db
        .customSelect(
          r'SELECT trust_resync_source($1, $2)',
          variables: [
            Variable<String>(sourceUserId),
            Variable<double>(_halfLifeSeconds),
          ],
        )
        .getSingle();
  }

  @override
  Future<void> forceRefreshAll() async {
    await _db
        .customSelect(
          r'SELECT trust_recompute_all($1)',
          variables: [Variable<double>(_halfLifeSeconds)],
        )
        .getSingle();
    await _meritrank.reset();
    await _meritrank.init();
  }

  @override
  Future<void> cutoverBackfillIfNeeded() async {
    final trustCount = await _db
        .customSelect(
          'SELECT count(*)::int AS c FROM user_trust_edge',
        )
        .map((r) => r.read<int>('c'))
        .getSingle();
    if (trustCount > 0) return;

    final votes = await _db
        .customSelect(
          'SELECT subject, object, amount FROM vote_user WHERE amount <> 0',
        )
        .get();
    if (votes.isEmpty) return;

    for (final vote in votes) {
      final amount = vote.read<int>('amount');
      final bin = voteAmountToBin(amount);
      if (bin == null) continue;
      await _applyEvidenceItem(
        subjectUserId: vote.read<String>('subject'),
        item: TrustEvidence(
          targetUserId: vote.read<String>('object'),
          bin: bin,
          count: kTrustVoteEvidenceCount,
        ),
      );
    }

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
          (v) => v.subject.id(subjectUserId) & v.object.id(objectUserId),
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
            (v) => v.subject.id(subjectUserId) & v.object.id(objectUserId),
          )
          .update((o) => o(amount: Value(newAmount)));
    }

    final bin = voteAmountToBin(newAmount);
    if (bin == null) return;

    await _applyEvidenceItem(
      subjectUserId: subjectUserId,
      item: TrustEvidence(
        targetUserId: objectUserId,
        bin: bin,
        count: kTrustVoteEvidenceCount,
      ),
    );
  }

  Future<int> _voteAmount({
    required String subjectUserId,
    required String objectUserId,
  }) async {
    final vote = await _db.managers.voteUsers
        .filter(
          (row) => row.subject.id(subjectUserId) & row.object.id(objectUserId),
        )
        .getSingleOrNull();
    return vote?.amount ?? 0;
  }

  Future<void> _applyEvidenceItem({
    required String subjectUserId,
    required TrustEvidence item,
  }) => _db
      .customSelect(
        r'SELECT trust_apply_evidence($1, $2, $3, $4, $5, $6)',
        variables: [
          Variable<String>(subjectUserId),
          Variable<String>(item.targetUserId),
          Variable<String>(item.bin.key),
          Variable<double>(item.count),
          Variable<double>(_halfLifeSeconds),
          Variable<double>(_epsilon),
        ],
      )
      .getSingle();
}
