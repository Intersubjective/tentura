import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';

/// One row of `beacon_fact_card_revision` (issue #181 plan §14.2): a single
/// text version of a pinned fact, tagged with how it came to be.
sealed class BeaconFactHistoryEntry {
  const BeaconFactHistoryEntry({
    required this.id,
    required this.factCardId,
    required this.seq,
    required this.factText,
    required this.actorId,
    required this.createdAt,
  });

  final String id;
  final String factCardId;
  final int seq;
  final String factText;
  final String? actorId;
  final DateTime createdAt;

  /// Mirrors server `BeaconFactCardRevisionKindBits`.
  int get kind;
}

/// The fact's original text, set when it was pinned.
final class BeaconFactHistoryCreated extends BeaconFactHistoryEntry {
  const BeaconFactHistoryCreated({
    required super.id,
    required super.factCardId,
    required super.seq,
    required super.factText,
    required super.actorId,
    required super.createdAt,
  });

  @override
  int get kind => BeaconFactCardRevisionKindBits.created;
}

/// The fact's text was corrected by an editor.
final class BeaconFactHistoryEdited extends BeaconFactHistoryEntry {
  const BeaconFactHistoryEdited({
    required super.id,
    required super.factCardId,
    required super.seq,
    required super.factText,
    required super.actorId,
    required super.createdAt,
  });

  @override
  int get kind => BeaconFactCardRevisionKindBits.edited;
}

/// A prior revision's text was restored as the new head.
final class BeaconFactHistoryRestored extends BeaconFactHistoryEntry {
  const BeaconFactHistoryRestored({
    required super.id,
    required super.factCardId,
    required super.seq,
    required super.factText,
    required super.actorId,
    required super.createdAt,
    required this.restoredFromSeq,
  });

  final int restoredFromSeq;

  @override
  int get kind => BeaconFactCardRevisionKindBits.restored;
}

/// A baseline revision backfilled from data that predates fact history
/// (plan §14.6: no author, no reliable timestamp of the original edit).
final class BeaconFactHistoryImported extends BeaconFactHistoryEntry {
  const BeaconFactHistoryImported({
    required super.id,
    required super.factCardId,
    required super.seq,
    required super.factText,
    required super.actorId,
    required super.createdAt,
  });

  @override
  int get kind => BeaconFactCardRevisionKindBits.imported;
}
