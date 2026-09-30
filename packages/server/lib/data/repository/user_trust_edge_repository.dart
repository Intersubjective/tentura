import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/meritrank_repository_port.dart';
import 'package:tentura_server/domain/port/user_trust_edge_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: UserTrustEdgeRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class UserTrustEdgeRepository implements UserTrustEdgeRepositoryPort {
  UserTrustEdgeRepository(
    this._db,
    // Kept for DI signature stability; publication is queue-driven.
    // ignore: avoid_unused_constructor_parameters
    MeritrankRepositoryPort meritrank, {
    // Kept for DI signature stability; unused.
    // ignore: avoid_unused_constructor_parameters
    WitnessWindowPort? witnessWindow,
  });

  final TenturaDb _db;

  @override
  Future<void> setVoteAmountAndApplyEvidence({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) => _db.transaction(
    () => _setVoteAmountCore(subjectUserId, objectUserId, newAmount),
  );

  @override
  Future<void> setVoteAmountAndApplyEvidenceInTransaction({
    required String subjectUserId,
    required String objectUserId,
    required int newAmount,
  }) => _setVoteAmountCore(subjectUserId, objectUserId, newAmount);

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
    await _setVoteAmountCore(subjectUserId, objectUserId, newAmount);
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

  Future<void> _setVoteAmountCore(
    String subjectUserId,
    String objectUserId,
    int newAmount,
  ) async {
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

    await _db.customStatement(
      r'SELECT public.trust_project_pair($1, $2)',
      [subjectUserId, objectUserId],
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
