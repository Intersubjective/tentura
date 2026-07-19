import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';
import 'package:tentura_server/domain/trust/trust_source_type.dart';

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
    this._trustEvidenceRepository,
  );

  final TenturaDb _db;
  final MeritrankRepositoryPort _meritrank;
  final TrustEvidenceRepositoryPort _trustEvidenceRepository;

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
          r'SELECT trust_resync_source($1)',
          variables: [Variable<String>(sourceUserId)],
        )
        .getSingle();
  }

  @override
  Future<void> cutoverBackfillIfNeeded() async {
    final trustCount = await _db
        .customSelect(
          'SELECT count(*)::int AS c FROM user_trust_source_edge',
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

    final at = DateTime.timestamp();
    for (final vote in votes) {
      final amount = vote.read<int>('amount');
      final bin = voteAmountToBin(amount);
      if (bin == null) continue;
      await _trustEvidenceRepository.record(
        TrustEvidenceBatch(
          sourceUserId: vote.read<String>('subject'),
          at: at,
          items: [
            TrustEvidence(
              targetUserId: vote.read<String>('object'),
              bin: bin,
              count: kTrustVoteEvidenceCount,
              context: TrustContext.personal,
              sourceType: TrustSourceType.userVote,
            ),
          ],
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

    await _trustEvidenceRepository.record(
      TrustEvidenceBatch(
        sourceUserId: subjectUserId,
        at: DateTime.timestamp(),
        items: [
          TrustEvidence(
            targetUserId: objectUserId,
            bin: bin,
            count: kTrustVoteEvidenceCount,
            context: TrustContext.personal,
            sourceType: TrustSourceType.userVote,
          ),
        ],
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
}
