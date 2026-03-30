import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/candidate_involvement.dart';
import '../../domain/entity/forward_candidate.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'forward_state.freezed.dart';

enum ForwardFilter { all, bestNext, unseen, alreadyInvolved }

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
    @Default('') String searchQuery,
    @Default([]) List<ForwardCandidate> candidates,
    @Default({}) Set<String> selectedIds,
    @Default(<String, String>{}) Map<String, String> perRecipientNotes,
    @Default(ForwardFilter.all) ForwardFilter activeFilter,
    Beacon? beacon,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ForwardState;

  const ForwardState._();

  static int _compareByMr(ForwardCandidate a, ForwardCandidate b) =>
      b.mrScore.compareTo(a.mrScore);

  static void _sortByMr(List<ForwardCandidate> list) =>
      list.sort(_compareByMr);

  List<ForwardCandidate> _searchFilteredBase() {
    if (searchQuery.isEmpty) return candidates;
    final q = searchQuery.toLowerCase();
    return candidates.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  List<ForwardCandidate> _filteredFlatFromBase(List<ForwardCandidate> base) {
    final Iterable<ForwardCandidate> picked;
    switch (activeFilter) {
      case ForwardFilter.all:
        return [];
      case ForwardFilter.bestNext:
        picked = base.where((c) => c.canForwardTo && c.isUnseen);
      case ForwardFilter.unseen:
        picked = base.where((c) => c.isUnseen);
      case ForwardFilter.alreadyInvolved:
        picked = base.where(
          (c) =>
              c.involvement != CandidateInvolvement.unseen &&
              c.involvement != CandidateInvolvement.author,
        );
    }
    final list = picked.toList();
    _sortByMr(list);
    return list;
  }

  ForwardBeaconListSections computeBeaconListSections() {
    final base = _searchFilteredBase();
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
      } else if (c.canForwardTo && c.isUnseen) {
        recommended.add(c);
      } else if (!c.isUnseen) {
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
