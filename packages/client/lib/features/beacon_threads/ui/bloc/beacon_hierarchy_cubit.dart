import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/domain/use_case/beacon_hierarchy_case.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'beacon_hierarchy_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

class BeaconHierarchyCubit extends Cubit<BeaconHierarchyState> {
  BeaconHierarchyCubit({
    required String beaconId,
    BeaconHierarchyCase? hierarchyCase,
  }) : _beaconId = beaconId,
       _hierarchy = hierarchyCase ?? GetIt.I<BeaconHierarchyCase>(),
       super(const BeaconHierarchyState());

  final String _beaconId;
  final BeaconHierarchyCase _hierarchy;

  int _loadGeneration = 0;

  Future<void> load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final capabilities = await _hierarchy.fetchCapabilities(
        beaconId: _beaconId,
      );
      if (generation != _loadGeneration || isClosed) return;

      if (!capabilities.canListChildren) {
        emit(
          state.copyWith(
            capabilities: capabilities,
            active: const BeaconHierarchyGroupSlice(),
            finished: const BeaconHierarchyGroupSlice(),
            deleted: const BeaconHierarchyGroupSlice(expanded: false),
            capabilitiesError: null,
            status: const StateIsSuccess(),
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          capabilities: capabilities,
          capabilitiesError: null,
          status: const StateIsSuccess(),
        ),
      );
      await _loadGroup(
        BeaconHierarchyChildGroup.active,
        generation: generation,
        reset: true,
      );
      if (generation != _loadGeneration || isClosed) return;
      await _loadGroup(
        BeaconHierarchyChildGroup.finished,
        generation: generation,
        reset: true,
      );
    } on Object catch (e) {
      if (generation != _loadGeneration || isClosed) return;
      emit(
        state.copyWith(
          capabilitiesError: e,
          status: const StateIsSuccess(),
        ),
      );
    }
  }

  Future<void> loadParentReference() async {
    emit(
      state.copyWith(
        parentReferenceLoading: true,
        parentReferenceError: null,
      ),
    );
    try {
      final reference = await _hierarchy.fetchParentReference(
        beaconId: _beaconId,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          parentReference: reference,
          parentReferenceLoading: false,
        ),
      );
    } on Object catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          parentReferenceLoading: false,
          parentReferenceError: e,
        ),
      );
    }
  }

  Future<void> refreshGroup(BeaconHierarchyChildGroup group) =>
      _loadGroup(group, generation: _loadGeneration, reset: true);

  Future<void> loadMore(BeaconHierarchyChildGroup group) {
    final slice = state.sliceFor(group);
    if (slice.loading || slice.loadingMore || !slice.hasMore) {
      return Future<void>.value();
    }
    return _loadGroup(
      group,
      generation: _loadGeneration,
      reset: false,
      after: slice.nextCursor,
    );
  }

  void setDeletedExpanded(bool expanded) {
    emit(state.copyWith(deleted: state.deleted.copyWith(expanded: expanded)));
    if (expanded && state.deleted.items.isEmpty && !state.deleted.loading) {
      unawaited(
        _loadGroup(
          BeaconHierarchyChildGroup.deleted,
          generation: _loadGeneration,
          reset: true,
        ),
      );
    }
  }

  void evictHierarchyAccess() {
    emit(
      const BeaconHierarchyState(
        status: const StateIsSuccess(),
      ),
    );
  }

  Future<void> _loadGroup(
    BeaconHierarchyChildGroup group, {
    required int generation,
    required bool reset,
    String? after,
  }) async {
    if (!state.canListChildren) return;

    final previous = state.sliceFor(group);
    final loadingSlice = previous.copyWith(
      loading: reset,
      loadingMore: !reset,
      error: reset ? null : previous.error,
    );
    emit(_replaceSlice(group, loadingSlice));

    try {
      final page = await _hierarchy.fetchChildren(
        parentBeaconId: _beaconId,
        group: group,
        after: after,
      );
      if (generation != _loadGeneration || isClosed) return;

      final merged = reset
          ? page.summaries
          : _dedupeByBeaconId([...previous.items, ...page.summaries]);
      emit(
        _replaceSlice(
          group,
          previous.copyWith(
            items: merged,
            nextCursor: page.nextCursor,
            loading: false,
            loadingMore: false,
            error: null,
          ),
        ),
      );
    } on BeaconHierarchyException catch (e) {
      if (generation != _loadGeneration || isClosed) return;
      emit(
        _replaceSlice(
          group,
          previous.copyWith(
            loading: false,
            loadingMore: false,
            error: e,
            items: reset ? const [] : previous.items,
          ),
        ),
      );
    } on Object catch (e) {
      if (generation != _loadGeneration || isClosed) return;
      emit(
        _replaceSlice(
          group,
          previous.copyWith(
            loading: false,
            loadingMore: false,
            error: e,
            items: reset ? const [] : previous.items,
          ),
        ),
      );
    }
  }

  BeaconHierarchyState _replaceSlice(
    BeaconHierarchyChildGroup group,
    BeaconHierarchyGroupSlice slice,
  ) => switch (group) {
    BeaconHierarchyChildGroup.active => state.copyWith(active: slice),
    BeaconHierarchyChildGroup.finished => state.copyWith(finished: slice),
    BeaconHierarchyChildGroup.deleted => state.copyWith(deleted: slice),
  };

  List<BeaconHierarchySummary> _dedupeByBeaconId(
    List<BeaconHierarchySummary> items,
  ) {
    final seen = <String>{};
    final out = <BeaconHierarchySummary>[];
    for (final item in items) {
      if (seen.add(item.beaconId)) {
        out.add(item);
      }
    }
    return out;
  }
}
