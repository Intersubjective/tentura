/// Shared coordination phase for STATUS line (identical per visibility tier).
///
/// See `docs/beacon-status-line-rationale.md` for White / Latane-Darley funnel.
enum BeaconCoordinationPhase {
  blocked,
  wrappingUp,
  needsMoreHelp,
  enoughHelpInMotion,
  offersAwaitingAuthor,
  coordinating,
  lookingForHelpers,
  closed,
  cancelled,
  draft,
  openFloor,
}

/// Coordination netdom (room members) vs public feed visibility.
enum BeaconVisibilityTier {
  coordination,
  public,
}

/// Slot2 semantic kind — presenter maps to localized fragments.
enum BeaconPhaseSlot2Kind {
  blockerNeedsClearing,
  courtAuthor,
  reviewCountdown,
  freshness,
  noOffersYet,
  lifecycleEndedAt,
  none,
}

/// Phase-suggested primary action; adapters gate by viewer capability.
enum BeaconPhasePrimaryAction {
  resolveBlocker,
  reviewOffers,
  forward,
  offerHelp,
  postUpdate,
  reviewContributions,
  none,
}

/// Anti-redundancy hints for STATUS × NOW × YOU rows.
class BeaconPhaseRowHarmony {
  const BeaconPhaseRowHarmony({
    this.suppressNowPlaceholder = false,
    this.suppressYouAwaitingAuthor = false,
    this.preferBlockedYouSegment = false,
    this.showBlockedTitleInNowSubline = false,
  });

  final bool suppressNowPlaceholder;
  final bool suppressYouAwaitingAuthor;
  final bool preferBlockedYouSegment;
  final bool showBlockedTitleInNowSubline;

  static const empty = BeaconPhaseRowHarmony();
}

/// Output of [deriveBeaconCoordinationPhase].
class BeaconCoordinationPhaseResult {
  const BeaconCoordinationPhaseResult({
    required this.phase,
    required this.suggestedAction,
    required this.rowHarmony,
    this.slot2Kind = BeaconPhaseSlot2Kind.none,
    this.reviewClosesAt,
    this.lastActivityAt,
    this.lifecycleEndedAt,
  });

  final BeaconCoordinationPhase phase;
  final BeaconPhaseSlot2Kind slot2Kind;
  final BeaconPhasePrimaryAction suggestedAction;
  final BeaconPhaseRowHarmony rowHarmony;

  /// For presenter review countdown slot2.
  final DateTime? reviewClosesAt;

  /// For presenter freshness slot2 (days quiet / active today).
  final DateTime? lastActivityAt;

  /// When lifecycle became closed or cancelled (`beacon.updatedAt`).
  final DateTime? lifecycleEndedAt;

  bool get isNeverEmpty => phase != BeaconCoordinationPhase.openFloor ||
      suggestedAction != BeaconPhasePrimaryAction.none;
}
