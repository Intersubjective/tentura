import 'beacon_fact_card_entity.dart';

/// Result of a fact-card edit/restore write (plan §14.5).
sealed class FactEditOutcome {
  const FactEditOutcome();
}

final class FactEditApplied extends FactEditOutcome {
  const FactEditApplied({required this.newSeq});

  final int newSeq;
}

/// Text unchanged; nothing written.
final class FactEditNoOp extends FactEditOutcome {
  const FactEditNoOp({required this.currentSeq});

  final int currentSeq;
}

final class FactEditNotFound extends FactEditOutcome {
  const FactEditNotFound();
}

final class FactEditRemoved extends FactEditOutcome {
  const FactEditRemoved();
}

final class FactEditRateLimited extends FactEditOutcome {
  const FactEditRateLimited();
}

/// The caller's base seq is stale.
final class FactEditConflict extends FactEditOutcome {
  const FactEditConflict({required this.currentSeq});

  final int currentSeq;
}

/// The revision to restore from does not exist.
final class FactRestoreSourceMissing extends FactEditOutcome {
  const FactRestoreSourceMissing();
}

/// Result of pinning a message as a fact card.
sealed class FactPinOutcome {
  const FactPinOutcome();
}

final class FactPinned extends FactPinOutcome {
  const FactPinned({required this.entity});

  final BeaconFactCardEntity entity;
}

final class FactAlreadyPinned extends FactPinOutcome {
  const FactAlreadyPinned({required this.existingFactCardId});

  final String existingFactCardId;
}
