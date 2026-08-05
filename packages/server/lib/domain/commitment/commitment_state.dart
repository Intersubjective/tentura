import 'package:tentura_server/consts/commitment_consts.dart';

import 'commitment_event.dart';
import 'commitment_event_kind.dart';

enum CommitmentStakeState { none, offered, acknowledged, softened, exited, released }

List<CommitmentEvent> _sortedBySeq(List<CommitmentEvent> events) {
  final copy = List<CommitmentEvent>.from(events);
  copy.sort((a, b) => a.seq.compareTo(b.seq));
  return copy;
}

bool everAcknowledged(
  List<CommitmentEvent> events, {
  Duration grace = kCommitmentGracePeriod,
}) {
  final sorted = _sortedBySeq(events);
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i].kind != CommitmentEventKind.acknowledged) continue;
    final n = i + 1;
    if (n < sorted.length &&
        sorted[n].kind == CommitmentEventKind.withdrawnByHelper &&
        sorted[n].createdAt.difference(sorted[i].createdAt) <= grace) {
      continue;
    }
    return true;
  }
  return false;
}

CommitmentStakeState currentStakeState(List<CommitmentEvent> events) {
  var state = CommitmentStakeState.none;
  for (final event in _sortedBySeq(events)) {
    state = switch (event.kind) {
      CommitmentEventKind.offered => CommitmentStakeState.offered,
      CommitmentEventKind.acknowledged => CommitmentStakeState.acknowledged,
      CommitmentEventKind.acknowledgementSoftened =>
        CommitmentStakeState.softened,
      CommitmentEventKind.withdrawnByHelper => CommitmentStakeState.exited,
      CommitmentEventKind.releasedByAuthor => CommitmentStakeState.released,
      CommitmentEventKind.blockedCleanup => CommitmentStakeState.exited,
      CommitmentEventKind.removedFromChat => state,
      CommitmentEventKind.readmittedToChat => state,
      CommitmentEventKind.unansweredAtClose => state,
    };
  }
  return state;
}

bool hasCurrentStake(
  List<CommitmentEvent> events, {
  required bool hasActiveOffer,
}) =>
    currentStakeState(events) == CommitmentStakeState.acknowledged &&
    hasActiveOffer;
