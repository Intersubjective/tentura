import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_child_group.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
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
       super(const BeaconHierarchyState()) {
    _hierarchyChangesSub = _hierarchy
        .hierarchyChangesFor(_beaconId)
        .listen(_onHierarchyChanged);
    _catchUpsSub = _hierarchy.catchUps.listen((_) => _scheduleSilentRefresh());
  }

  static const _refreshDebounce = Duration(milliseconds: 100);

  final String _beaconId;
  final BeaconHierarchyCase _hierarchy;

  late final StreamSubscription<RealtimeEntityChange> _hierarchyChangesSub;
  late final StreamSubscription<void> _catchUpsSub;

  Timer? _refreshTimer;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _queuedRequestWasExplicit = false;
  int _loadGeneration = 0;

  void _onHierarchyChanged(RealtimeEntityChange _) => _scheduleSilentRefresh();

  void _scheduleSilentRefresh() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (!isClosed) {
        unawaited(_runSilentRefresh());
      }
    });
  }

  Future<void> load({bool silent = false}) async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      if (!silent) {
        _queuedRequestWasExplicit = true;
        emit(state.copyWith(status: const StateIsLoading()));
      }
      return;
    }
    await _runLoad(silent: silent);
  }

  /// Runs the deferred rerun requested while a refresh was already
  /// in-flight (queued by [load] or a coalesced realtime hint). The
  /// rerun itself is always the silent snapshot refresh, but if the
  /// deferred request was an explicit (non-silent) [load] call — which
  /// already flipped `status` to loading before returning — restore it
  /// to success afterward, so an explicit load queued behind another
  /// refresh can never leave `status` stuck at loading.
  Future<void> _runQueuedRerunIfNeeded() async {
    if (!_refreshQueued || isClosed) return;
    _refreshQueued = false;
    final wasExplicit = _queuedRequestWasExplicit;
    _queuedRequestWasExplicit = false;
    await _runSilentRefresh();
    if (wasExplicit && !isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> _runLoad({required bool silent}) async {
    _refreshInFlight = true;
    _refreshQueued = false;
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
    } finally {
      _refreshInFlight = false;
      unawaited(_runQueuedRerunIfNeeded());
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

  Future<void> _runSilentRefresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    _refreshQueued = false;
    final generation = ++_loadGeneration;
    try {
      final capabilities = await _hierarchy.fetchCapabilities(
        beaconId: _beaconId,
      );
      if (generation != _loadGeneration || isClosed) return;

      if (!capabilities.canListChildren) {
        if (state.canListChildren ||
            state.active.items.isNotEmpty ||
            state.finished.items.isNotEmpty ||
            state.parentReference != null) {
          evictHierarchyAccess();
        } else {
          emit(
            state.copyWith(
              capabilities: capabilities,
              capabilitiesError: null,
            ),
          );
        }
        await _refreshParentReferenceSilent(generation);
        return;
      }

      emit(
        state.copyWith(
          capabilities: capabilities,
          capabilitiesError: null,
        ),
      );
      await _loadGroup(
        BeaconHierarchyChildGroup.active,
        generation: generation,
        reset: true,
        silent: true,
      );
      if (generation != _loadGeneration || isClosed) return;
      await _loadGroup(
        BeaconHierarchyChildGroup.finished,
        generation: generation,
        reset: true,
        silent: true,
      );
      if (generation != _loadGeneration || isClosed) return;
      await _refreshParentReferenceSilent(generation);
    } on Object catch (_) {
      // Keep the usable snapshot; a later hint or catch-up retries.
    } finally {
      _refreshInFlight = false;
      unawaited(_runQueuedRerunIfNeeded());
    }
  }

  Future<void> _refreshParentReferenceSilent(int generation) async {
    if (state.parentReference == null &&
        !state.parentReferenceLoading &&
        state.parentReferenceError == null) {
      return;
    }
    try {
      final reference = await _hierarchy.fetchParentReference(
        beaconId: _beaconId,
      );
      if (generation != _loadGeneration || isClosed) return;
      emit(
        state.copyWith(
          parentReference: reference,
          parentReferenceLoading: false,
          parentReferenceError: null,
        ),
      );
    } on BeaconHierarchyException catch (_) {
      if (generation != _loadGeneration || isClosed) return;
      evictHierarchyAccess();
    } on Object catch (_) {
      // Transient failure retains the current parent-reference snapshot.
    }
  }

  Future<void> _loadGroup(
    BeaconHierarchyChildGroup group, {
    required int generation,
    required bool reset,
    String? after,
    bool silent = false,
  }) async {
    if (!state.canListChildren && silent) {
      final capabilities = state.capabilities;
      if (capabilities == null || !capabilities.canListChildren) return;
    } else if (!state.canListChildren) {
      return;
    }

    final previous = state.sliceFor(group);
    final loadingSlice = previous.copyWith(
      loading: reset && !silent,
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
      if (silent) {
        evictHierarchyAccess();
        return;
      }
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
            error: silent ? previous.error : e,
            items: reset && !silent ? const [] : previous.items,
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

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await _hierarchyChangesSub.cancel();
    await _catchUpsSub.cancel();
    return super.close();
  }
}
