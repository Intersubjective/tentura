import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'forward_state.freezed.dart';

enum ForwardFilter { all, bestNext, unseen, alreadyInvolved }

/// Mutually exclusive load lifecycle for forward candidate lists.
///
/// Separate from [StateStatus] on [ForwardState], which tracks send/edit/cancel
/// actions only.
sealed class ForwardCandidatesLoad {
  const ForwardCandidatesLoad();
}

class ForwardCandidatesLoading extends ForwardCandidatesLoad {
  const ForwardCandidatesLoading();
}

class ForwardCandidatesReady extends ForwardCandidatesLoad {
  const ForwardCandidatesReady();
}

class ForwardCandidatesEmpty extends ForwardCandidatesLoad {
  const ForwardCandidatesEmpty();
}

class ForwardCandidatesError extends ForwardCandidatesLoad {
  const ForwardCandidatesError(this.error);

  final Object error;
}

/// Result of the most recent forward call (embedded create + non-embedded send).
@immutable
class ForwardDeliveryOutcome {
  const ForwardDeliveryOutcome({
    required this.requestedRecipientIds,
    required this.deliveredRecipientIds,
    required this.availabilitySkippedRecipientIds,
    this.failed = false,
  });

  final List<String> requestedRecipientIds;
  final List<String> deliveredRecipientIds;
  final List<String> availabilitySkippedRecipientIds;
  final bool failed;

  int get requestedCount => requestedRecipientIds.length;

  int get deliveredCount => deliveredRecipientIds.length;

  int get availabilitySkippedCount => availabilitySkippedRecipientIds.length;
}

/// Counts for compact scope links (full candidate list; scope only).
@immutable
class ForwardScopeCounts {
  const ForwardScopeCounts({
    required this.unseen,
    required this.involved,
  });

  final int unseen;
  final int involved;
}

/// Built once per UI rebuild via [ForwardState.computeBeaconListSections] —
/// single search pass, one sort per bucket (no repeated getter work).
class ForwardBeaconListSections {
  const ForwardBeaconListSections({
    required this.recommended,
    required this.other,
    required this.unavailable,
    required this.notReachable,
    required this.filteredFlatList,
  });

  final List<ForwardCandidate> recommended;
  final List<ForwardCandidate> other;

  /// Reachable beacon author or someone who declined — not in [other].
  final List<ForwardCandidate> unavailable;
  final List<ForwardCandidate> notReachable;

  /// Non-empty when [ForwardFilter] is not [ForwardFilter.all].
  final List<ForwardCandidate> filteredFlatList;

  bool get isEmptyAllLayout =>
      recommended.isEmpty &&
      other.isEmpty &&
      unavailable.isEmpty &&
      notReachable.isEmpty;
}

@freezed
abstract class ForwardState extends StateBase with _$ForwardState {
  const factory ForwardState({
    @Default('') String beaconId,
    @Default('') String context,
    @Default('') String note,
    @Default([]) List<ForwardCandidate> candidates,
    @Default([]) List<ForwardCandidate> lineageSuggestions,
    @Default({}) Set<String> selectedIds,
    @Default(<String>{}) Set<String> droppedPreselectedIds,
    @Default(<String, String>{}) Map<String, String> perRecipientNotes,
    @Default(<String>{}) Set<String> skippedPersonalNoteIds,
    @Default(<String>[]) List<String> lastDeliveredRecipientIds,
    @Default(<String, List<String>>{})
    Map<String, List<String>> recipientReasons,
    @Default(ForwardFilter.unseen) ForwardFilter activeFilter,
    Beacon? beacon,
    @Default(StateIsSuccess()) StateStatus status,
    @Default(ForwardCandidatesLoading()) ForwardCandidatesLoad candidatesLoad,
    String? editingRecipientId,
    @Default('') String editNote,
    List<String>? editReasons,
    ForwardDeliveryOutcome? lastDeliveryOutcome,
    @Default(false) bool hasMyOutgoingForward,
    @Default([]) List<ForwardBandRow> band,
  }) = _ForwardState;

  const ForwardState._();

  Set<String> get bandMemberIds => band.map((row) => row.userId).toSet();

  static int _compareByMr(ForwardCandidate a, ForwardCandidate b) =>
      b.mrScore.compareTo(a.mrScore);

  static void _sortByMr(List<ForwardCandidate> list) => list.sort(_compareByMr);

  /// Full-screen search: filter [candidates] by name/description (MR-sorted).
  static List<ForwardCandidate> filterCandidatesByQuery(
    List<ForwardCandidate> candidates,
    String query,
  ) {
    final trimmed = query.trim();
    final list = trimmed.isEmpty
        ? List<ForwardCandidate>.from(candidates)
        : candidates
              .where(
                (c) =>
                    c.profile.shownName.toLowerCase().contains(
                      trimmed.toLowerCase(),
                    ) ||
                    c.displayName.toLowerCase().contains(
                      trimmed.toLowerCase(),
                    ) ||
                    c.profile.description.toLowerCase().contains(
                      trimmed.toLowerCase(),
                    ),
              )
              .toList();
    _sortByMr(list);
    return list;
  }

  /// Involved / touched path: anyone except purely unseen recipients and the
  /// beacon author (candidates may still list the author for some graphs).
  static bool matchesInvolvedScope(ForwardCandidate c) =>
      c.involvement != CandidateInvolvement.unseen &&
      c.involvement != CandidateInvolvement.author;

  List<ForwardCandidate> _candidatesBase() =>
      List<ForwardCandidate>.from(candidates);

  /// Main + lineage rows deduped by id (main list wins over lineage row).
  List<ForwardCandidate> _mergedCandidatesForInvolvedScope() {
    final byId = {for (final c in _candidatesBase()) c.id: c};
    for (final c in lineageSuggestions) {
      byId.putIfAbsent(c.id, () => c);
    }
    return byId.values.toList();
  }

  ForwardScopeCounts get scopeCounts {
    final base = _candidatesBase();
    return ForwardScopeCounts(
      unseen: base.where((c) => c.isUnseen).length,
      involved: base.where(matchesInvolvedScope).length,
    );
  }

  /// Recipients for the active scope, MR-sorted.
  ///
  /// Unseen / all scopes exclude lineage block rows (shown separately).
  /// Involved scope merges lineage rows so current-beacon involvement is
  /// visible even when the person also appears in lineage suggestions.
  List<ForwardCandidate> get visibleRecipients {
    final lineageIds = lineageSuggestions.map((c) => c.id).toSet();
    final bandIds = bandMemberIds;
    final Iterable<ForwardCandidate> picked;
    switch (activeFilter) {
      case ForwardFilter.all:
      case ForwardFilter.bestNext:
        picked = _candidatesBase()
            .where((c) => !lineageIds.contains(c.id))
            .where((c) => !bandIds.contains(c.id))
            .where((c) => c.canForwardTo);
      case ForwardFilter.unseen:
        picked = _candidatesBase()
            .where((c) => !lineageIds.contains(c.id))
            .where((c) => !bandIds.contains(c.id))
            .where((c) => c.isUnseen);
      case ForwardFilter.alreadyInvolved:
        picked = _mergedCandidatesForInvolvedScope().where(
          matchesInvolvedScope,
        );
    }
    final list = picked.toList();
    _sortByMr(list);
    return list;
  }

  List<ForwardCandidate> _filteredFlatFromBase(List<ForwardCandidate> base) {
    final Iterable<ForwardCandidate> picked;
    switch (activeFilter) {
      case ForwardFilter.all:
        return [];
      case ForwardFilter.bestNext:
        picked = base.where((c) => c.canForwardTo);
      case ForwardFilter.unseen:
        picked = base.where((c) => c.isUnseen);
      case ForwardFilter.alreadyInvolved:
        picked = base.where(matchesInvolvedScope);
    }
    final list = picked.toList();
    _sortByMr(list);
    return list;
  }

  ForwardBeaconListSections computeBeaconListSections() {
    final base = _candidatesBase();
    if (activeFilter != ForwardFilter.all) {
      return ForwardBeaconListSections(
        recommended: const [],
        other: const [],
        unavailable: const [],
        notReachable: const [],
        filteredFlatList: _filteredFlatFromBase(base),
      );
    }

    final recommended = <ForwardCandidate>[];
    final other = <ForwardCandidate>[];
    final unavailable = <ForwardCandidate>[];
    final notReachable = <ForwardCandidate>[];

    for (final c in base) {
      if (!c.isReachable) {
        notReachable.add(c);
      } else if (c.involvement == CandidateInvolvement.author ||
          c.involvement == CandidateInvolvement.declined) {
        unavailable.add(c);
      } else if (c.canForwardTo) {
        recommended.add(c);
      } else {
        other.add(c);
      }
    }

    _sortByMr(recommended);
    _sortByMr(other);
    _sortByMr(unavailable);
    _sortByMr(notReachable);

    return ForwardBeaconListSections(
      recommended: recommended,
      other: other,
      unavailable: unavailable,
      notReachable: notReachable,
      filteredFlatList: const [],
    );
  }

  int get selectedCount => selectedIds.length;
}
