import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';

/// One row of a fact card's history timeline (issue #181 plan §14.2):
/// a text revision ([BeaconFactHistoryEntry]) or a visibility/unpin event
/// ([BeaconFactHistoryEvent]). Mirrors the server union.
sealed class BeaconFactTimelineEntry {
  const BeaconFactTimelineEntry({
    required this.id,
    required this.actorId,
    required this.actorTitle,
    required this.createdAt,
  });

  /// Unique across revisions and events of one fact (timeline list key).
  final String id;
  final String? actorId;
  final String actorTitle;
  final DateTime createdAt;
}

/// A visibility change or unpin event on the fact.
final class BeaconFactHistoryEvent extends BeaconFactTimelineEntry {
  const BeaconFactHistoryEvent({
    required super.id,
    required super.actorId,
    required super.actorTitle,
    required super.createdAt,
    required this.type,
    this.visibilityFrom,
    this.visibilityTo,
  });

  /// A `BeaconActivityEventTypeBits` value.
  final int type;
  final int? visibilityFrom;
  final int? visibilityTo;
}

/// One row of `beacon_fact_card_revision` (issue #181 plan §14.2): a single
/// text version of a pinned fact, tagged with how it came to be.
sealed class BeaconFactHistoryEntry extends BeaconFactTimelineEntry {
  const BeaconFactHistoryEntry({
    required super.id,
    required this.factCardId,
    required this.seq,
    required this.factText,
    required super.actorId,
    required super.createdAt,
    super.actorTitle = '',
  });

  final String factCardId;
  final int seq;
  final String factText;

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
    super.actorTitle = '',
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
    super.actorTitle = '',
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
    super.actorTitle = '',
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
    super.actorTitle = '',
  });

  @override
  int get kind => BeaconFactCardRevisionKindBits.imported;
}

/// One page of a fact's history timeline, newest first; pass `nextCursor`
/// back as `before` to load the next (older) page.
typedef BeaconFactHistoryPage = ({
  List<BeaconFactTimelineEntry> entries,
  String? nextCursor,
});
