import 'package:tentura_server/consts/commitment_consts.dart';

import '../commitment/commitment_event.dart';
import '../commitment/commitment_event_kind.dart';

enum Departure {
  voluntary(1),
  removed(2);

  const Departure(this.dbValue);

  final int dbValue;
}

final class MemberState {
  const MemberState({
    required this.member,
    required this.active,
    this.departure,
  });

  final bool member;
  final bool active;
  final Departure? departure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemberState &&
          member == other.member &&
          active == other.active &&
          departure == other.departure;

  @override
  int get hashCode => Object.hash(member, active, departure);
}

/// Maps a helper's commitment events to membership snapshot fields (arch §5.3).
///
/// [now] is reserved for callers (e.g. closure at wall time); grace rollback
/// uses event timestamps only, matching [everAcknowledged].
MemberState reduce(
  List<CommitmentEvent> eventsInOrder, {
  required DateTime now,
}) {
  now;
  final sorted = List<CommitmentEvent>.from(eventsInOrder)
    ..sort((a, b) => a.seq.compareTo(b.seq));

  var member = false;
  var active = false;
  Departure? departure;

  for (var i = 0; i < sorted.length; i++) {
    final event = sorted[i];
    switch (event.kind) {
      case CommitmentEventKind.acknowledged:
        // Same grace pairing as everAcknowledged in commitment_state.dart.
        if (_ackGraceVoidedByImmediateWithdraw(sorted, i)) break;
        member = true;
        active = true;
        departure = null;
      case CommitmentEventKind.acknowledgementSoftened:
        break;
      case CommitmentEventKind.withdrawnByHelper:
        active = false;
        departure = Departure.voluntary;
      case CommitmentEventKind.releasedByAuthor:
      case CommitmentEventKind.removedFromChat:
      case CommitmentEventKind.blockedCleanup:
        active = false;
        departure = Departure.removed;
      case CommitmentEventKind.readmittedToChat:
        active = true;
        departure = null;
      case CommitmentEventKind.offered:
      case CommitmentEventKind.unansweredAtClose:
        break;
    }
  }

  return MemberState(member: member, active: active, departure: departure);
}

bool _ackGraceVoidedByImmediateWithdraw(
  List<CommitmentEvent> sorted,
  int ackIndex,
) {
  final n = ackIndex + 1;
  return n < sorted.length &&
      sorted[n].kind == CommitmentEventKind.withdrawnByHelper &&
      sorted[n].createdAt.difference(sorted[ackIndex].createdAt) <=
          kCommitmentGracePeriod;
}
