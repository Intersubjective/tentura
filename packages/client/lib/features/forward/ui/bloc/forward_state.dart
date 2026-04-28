import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'forward_state.freezed.dart';

enum ForwardFilter { all, bestNext, unseen, alreadyInvolved }

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
    @Default({}) Set<String> selectedIds,
    @Default(<String, String>{}) Map<String, String> perRecipientNotes,
    @Default(ForwardFilter.unseen) ForwardFilter activeFilter,
    Beacon? beacon,
    @Default([]) List<BeaconFactCard> publicFactCards,
    @Default({}) Set<String> selectedFactIdsForForward,
    @Default(false) bool includePublicStatusNote,
    @Default(false) bool viewerIsRoomMember,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ForwardState;

  const ForwardState._();

  static int _compareByMr(ForwardCandidate a, ForwardCandidate b) =>
      b.mrScore.compareTo(a.mrScore);

  static void _sortByMr(List<ForwardCandidate> list) =>
      list.sort(_compareByMr);

  /// Full-screen search: filter by name/description only (ignores scope tab).
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
                    c.title.toLowerCase().contains(trimmed.toLowerCase()) ||
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

  ForwardScopeCounts get scopeCounts {
    final base = _candidatesBase();
    return ForwardScopeCounts(
      unseen: base.where((c) => c.isUnseen).length,
      involved: base.where(matchesInvolvedScope).length,
    );
  }

  /// Recipients for the active scope, MR-sorted.
  List<ForwardCandidate> get visibleRecipients {
    final base = _candidatesBase();
    final Iterable<ForwardCandidate> picked;
    switch (activeFilter) {
      case ForwardFilter.all:
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
