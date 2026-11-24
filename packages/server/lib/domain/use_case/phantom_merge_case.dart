import 'package:injectable/injectable.dart';

import '../exception.dart';
import '../port/owner_graph_transaction_port.dart';
import '../port/phantom_merge_repository_port.dart';
import '../port/phantom_repository_port.dart';
import '../port/user_block_repository_port.dart';

sealed class PhantomMergeResult {}

final class PhantomMerged implements PhantomMergeResult {
  const PhantomMerged(this.mergeId);

  final String mergeId;
}

enum PhantomMergeGuardFailure implements PhantomMergeResult {
  inactive,
  self,
  blocked;

  String get reason => name;
}

@lazySingleton
final class PhantomMergeCase {
  const PhantomMergeCase(
    this._ownerGraph,
    this._phantoms,
    this._merges,
    this._blocks,
  );

  final OwnerGraphTransactionPort _ownerGraph;
  final PhantomRepositoryPort _phantoms;
  final PhantomMergeRepositoryPort _merges;
  final UserBlockRepositoryPort _blocks;

  Future<PhantomMergeResult> merge({
    required String ownerId,
    required String phantomId,
    required String userId,
    required int origin,
  }) {
    final mergeOrigin = PhantomMergeOrigin.fromCode(origin);
    final target = (ownerId: ownerId, phantomId: phantomId, userId: userId);
    return _ownerGraph.run({ownerId}, ownerId, (scope) async {
      if (mergeOrigin == PhantomMergeOrigin.manualLink) {
        final joiningName = await _phantoms.lockInvitesAndFindJoiningName(
          scope,
          ownerId: ownerId,
          id: phantomId,
        );
        if (joiningName != null) throw PhantomJoiningException(joiningName);
      }

      final displayName = await _merges.lockActive(scope, target);
      if (displayName == null) return PhantomMergeGuardFailure.inactive;
      if (userId == ownerId) return PhantomMergeGuardFailure.self;
      if (await _blocks.isBlockedPair(a: ownerId, b: userId)) {
        return PhantomMergeGuardFailure.blocked;
      }

      final mergeId = await _merges.merge(
        scope,
        target,
        origin: mergeOrigin,
        displayName: displayName,
      );
      return PhantomMerged(mergeId);
    });
  }
}
