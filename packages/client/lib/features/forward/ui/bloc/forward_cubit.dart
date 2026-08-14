import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/entity/forward_delivery_result.dart';
import '../../domain/entity/forward_inbound_source.dart';
import '../../domain/use_case/forward_case.dart';
import '../../domain/entity/forward_candidate.dart';
import '../../domain/exception.dart';
import '../message/forward_messages.dart';
import 'forward_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'forward_state.dart';

typedef ForwardTimerFactory =
    Timer Function(Duration duration, void Function() onFire);

typedef ForwardLifecycleListenerFactory =
    AppLifecycleListener Function({VoidCallback? onResume});

class ForwardCubit extends Cubit<ForwardState> {
  ForwardCubit({
    required String beaconId,
    String context = '',
    ForwardCase? forwardCase,
    UiEffectPort? effects,
    @visibleForTesting bool debugSkipInitialLoad = false,
    this.preselectLineageSuggestions = false,
    this.initialSelectedIds = const {},
    this.embedded = false,
    DateTime Function()? clock,
    ForwardTimerFactory? timerFactory,
    ForwardLifecycleListenerFactory? lifecycleListenerFactory,
  }) : _forwardCase =
           forwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<ForwardCase>()),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new,
       _lifecycleListenerFactory =
           lifecycleListenerFactory ??
           (({VoidCallback? onResume}) =>
               AppLifecycleListener(onResume: onResume)),
       super(ForwardState(beaconId: beaconId, context: context)) {
    if (!debugSkipInitialLoad) {
      unawaited(_loadCandidates());
    }
    _subscribeLiveUpdates();
    _maybeAttachLifecycleListener();
  }

  /// When true, first candidate load pre-checks lineage auto-select rows.
  final bool preselectLineageSuggestions;

  /// User-explicit recipient ids passed from profile → new request flow.
  final Set<String> initialSelectedIds;

  /// When true, [forward] does not emit [NavigateBack] (beacon-create tab host).
  final bool embedded;

  final ForwardCase? _forwardCase;

  final UiEffectPort _effects;

  final DateTime Function() _clock;

  final ForwardTimerFactory _timerFactory;

  final ForwardLifecycleListenerFactory _lifecycleListenerFactory;

  bool _appliedInitialLineagePreselect = false;
  bool _appliedInitialUserPreselect = false;
  bool _suppressForwardChangeReload = false;

  StreamSubscription<String>? _forwardChangesSub;

  StreamSubscription<void>? _contactChangesSub;

  StreamSubscription<void>? _blockChangesSub;

  Timer? _availabilityExpiryTimer;

  AppLifecycleListener? _lifecycleListener;

  DateTime _todayUtc() => availabilityTodayUtc(_clock);

  void _maybeAttachLifecycleListener() {
    if (BindingBase.debugBindingType() == null) {
      return;
    }
    _lifecycleListener = _lifecycleListenerFactory(onResume: _onAppResume);
  }

  void _subscribeLiveUpdates() {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    _forwardChangesSub = forwardCase.forwardChanges
        .where((id) => id == state.beaconId)
        .listen((_) {
          if (!isClosed && !_suppressForwardChangeReload) {
            unawaited(_loadCandidates(forceReload: true));
          }
        });
    _contactChangesSub = forwardCase.contactChanges.listen((_) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          candidates: ForwardCase.applyContactOverlayAll(state.candidates),
          lineageSuggestions: ForwardCase.applyContactOverlayAll(
            state.lineageSuggestions,
          ),
        ),
      );
    });
    _blockChangesSub = forwardCase.blockChanges.listen((_) {
      if (!isClosed) {
        unawaited(_loadCandidates(forceReload: true));
      }
    });
  }

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  bool _isInitialCandidatesLoad(ForwardCandidatesLoad load) =>
      load is ForwardCandidatesLoading || load is ForwardCandidatesError;

  ForwardCandidatesLoad _candidatesLoadFor({
    required List<ForwardCandidate> candidates,
    required List<ForwardCandidate> lineageSuggestions,
  }) =>
      candidates.isEmpty && lineageSuggestions.isEmpty
      ? const ForwardCandidatesEmpty()
      : const ForwardCandidatesReady();

  void _emitNavigateBack({Object? result}) {
    _effects.emit(NavigateBack(result: result));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  String? _loadMemoKey;

  Future<void> reloadCandidates({bool forceReload = true}) =>
      _loadCandidates(forceReload: forceReload);

  /// Retry after [ForwardCandidatesError] without clearing draft selections.
  Future<void> retryLoadCandidates() => reloadCandidates();

  Set<String> _selectableIdsOn(
    DateTime todayUtc, {
    required List<ForwardCandidate> candidates,
    required List<ForwardCandidate> lineageSuggestions,
  }) => {
    for (final c in candidates)
      if (c.canForwardToOn(todayUtc)) c.id,
    for (final c in lineageSuggestions)
      if (c.canForwardToOn(todayUtc)) c.id,
  };

  void _cancelAvailabilityExpiryTimer() {
    _availabilityExpiryTimer?.cancel();
    _availabilityExpiryTimer = null;
  }

  void _scheduleAvailabilityExpiryTimer() {
    _cancelAvailabilityExpiryTimer();
    final todayUtc = _todayUtc();
    DateTime? earliestResumeOn;
    for (final candidate in [
      ...state.candidates,
      ...state.lineageSuggestions,
    ]) {
      final resumeOn = candidate.profile.availability.resumeOn;
      if (resumeOn == null || !todayUtc.isBefore(resumeOn)) {
        continue;
      }
      if (earliestResumeOn == null || resumeOn.isBefore(earliestResumeOn)) {
        earliestResumeOn = resumeOn;
      }
    }
    if (earliestResumeOn == null) {
      return;
    }
    final delay = earliestResumeOn.difference(_clock().toUtc());
    if (delay.isNegative) {
      unawaited(_onAvailabilityBoundary());
      return;
    }
    _availabilityExpiryTimer = _timerFactory(delay, _onAvailabilityBoundary);
  }

  void _onAppResume() {
    if (isClosed) {
      return;
    }
    unawaited(_onAvailabilityBoundary());
  }

  Future<void> _onAvailabilityBoundary() async {
    if (isClosed) {
      return;
    }
    await _loadCandidates(forceReload: true);
    if (!isClosed) {
      _scheduleAvailabilityExpiryTimer();
    }
  }

  Future<void> _loadCandidates({bool forceReload = false}) async {
    final forwardCase = _forwardCase;
    if (forwardCase == null || isClosed) {
      return;
    }
    final isInitialLoad = _isInitialCandidatesLoad(state.candidatesLoad);
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        candidatesLoad: isInitialLoad
            ? const ForwardCandidatesLoading()
            : state.candidatesLoad,
      ),
    );
    try {
      final myId = await forwardCase.getCurrentAccountId();
      if (isClosed) {
        return;
      }
      final load = await forwardCase.loadForwardCandidates(
        beaconId: state.beaconId,
        context: state.context,
      );
      if (isClosed) {
        return;
      }
      final memoKey =
          '$myId|${state.beaconId}|${load.beacon.lineageParentBeaconId ?? ''}';
      if (!forceReload &&
          _loadMemoKey == memoKey &&
          state.candidates.isNotEmpty) {
        emit(state.copyWith(status: const StateIsSuccess()));
        return;
      }
      _loadMemoKey = memoKey;

      final todayUtc = _todayUtc();
      final selectableIds = _selectableIdsOn(
        todayUtc,
        candidates: load.candidates,
        lineageSuggestions: load.lineageSuggestions,
      );
      final preservedSelection = state.selectedIds.intersection(selectableIds);
      final shouldLineagePreselect =
          preselectLineageSuggestions &&
          !_appliedInitialLineagePreselect &&
          preservedSelection.isEmpty;
      final lineagePreselect = shouldLineagePreselect
          ? load.autoSelectIds.intersection(selectableIds)
          : const <String>{};
      if (preselectLineageSuggestions && !_appliedInitialLineagePreselect) {
        _appliedInitialLineagePreselect = true;
      }

      final shouldUserPreselect =
          initialSelectedIds.isNotEmpty &&
          !_appliedInitialUserPreselect &&
          preservedSelection.isEmpty;
      final userPreselect = shouldUserPreselect
          ? initialSelectedIds.intersection(selectableIds)
          : const <String>{};
      final droppedPreselected = shouldUserPreselect
          ? initialSelectedIds.difference(selectableIds)
          : state.droppedPreselectedIds;
      if (initialSelectedIds.isNotEmpty && !_appliedInitialUserPreselect) {
        _appliedInitialUserPreselect = true;
      }

      emit(
        state.copyWith(
          beacon: load.beacon,
          candidates: load.candidates,
          lineageSuggestions: load.lineageSuggestions,
          selectedIds: preservedSelection.isNotEmpty
              ? preservedSelection
              : {...lineagePreselect, ...userPreselect},
          droppedPreselectedIds: droppedPreselected,
          note: load.suggestedNote,
          hasMyOutgoingForward: load.hasMyOutgoingForward,
          band: load.band,
          candidatesLoad: _candidatesLoadFor(
            candidates: load.candidates,
            lineageSuggestions: load.lineageSuggestions,
          ),
          status: const StateIsSuccess(),
        ),
      );
      _scheduleAvailabilityExpiryTimer();
    } catch (e) {
      if (isInitialLoad) {
        if (!isClosed) {
          emit(
            state.copyWith(
              candidatesLoad: ForwardCandidatesError(e),
              status: const StateIsSuccess(),
            ),
          );
        }
      } else {
        _emitSnackError(e);
      }
    }
  }

  List<String> _stableRequestedRecipientOrder({
    required Set<String> droppedPreselectedIds,
    required Set<String> selectedIds,
    required List<ForwardCandidate> candidates,
    required List<ForwardCandidate> lineageSuggestions,
  }) {
    final seen = <String>{};
    final ordered = <String>[];

    void addId(String id) {
      if (seen.add(id)) {
        ordered.add(id);
      }
    }

    for (final candidate in candidates) {
      if (droppedPreselectedIds.contains(candidate.id)) {
        addId(candidate.id);
      }
    }
    for (final candidate in lineageSuggestions) {
      if (droppedPreselectedIds.contains(candidate.id)) {
        addId(candidate.id);
      }
    }
    for (final id in droppedPreselectedIds) {
      addId(id);
    }
    for (final candidate in candidates) {
      if (selectedIds.contains(candidate.id)) {
        addId(candidate.id);
      }
    }
    for (final candidate in lineageSuggestions) {
      if (selectedIds.contains(candidate.id)) {
        addId(candidate.id);
      }
    }
    for (final id in selectedIds) {
      addId(id);
    }
    return ordered;
  }

  ForwardDeliveryOutcome _buildDeliveryOutcome({
    required List<String> requestedRecipientIds,
    required List<String> deliveredRecipientIds,
    required List<String> availabilitySkippedRecipientIds,
    bool failed = false,
  }) => ForwardDeliveryOutcome(
    requestedRecipientIds: requestedRecipientIds,
    deliveredRecipientIds: deliveredRecipientIds,
    availabilitySkippedRecipientIds: availabilitySkippedRecipientIds,
    failed: failed,
  );

  void _emitDeliveryMessage(ForwardDeliveryOutcome outcome) {
    if (outcome.failed) {
      return;
    }
    final delivered = outcome.deliveredCount;
    final requested = outcome.requestedCount;
    final skipped = outcome.availabilitySkippedCount;
    if (skipped == 0) {
      _effects.emit(ShowMessage(ForwardSentMessage(delivered)));
      return;
    }
    if (skipped == 1) {
      final skippedId = outcome.availabilitySkippedRecipientIds.single;
      final candidate = _findCandidate(skippedId);
      final skippedName = candidate?.profile.shownName.trim().isNotEmpty == true
          ? candidate!.profile.shownName
          : skippedId;
      _effects.emit(
        ShowMessage(
          ForwardPartialDeliveryMessage(
            deliveredCount: delivered,
            requestedCount: requested,
            skippedName: skippedName,
          ),
        ),
      );
      return;
    }
    _effects.emit(
      ShowMessage(
        ForwardPartialDeliveryManyMessage(
          deliveredCount: delivered,
          requestedCount: requested,
          skippedCount: skipped,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    _cancelAvailabilityExpiryTimer();
    _lifecycleListener?.dispose();
    await _forwardChangesSub?.cancel();
    await _contactChangesSub?.cancel();
    await _blockChangesSub?.cancel();
    return super.close();
  }

  void clearLineageSuggestions() {
    final lineageIds = state.lineageSuggestions.map((c) => c.id).toSet();
    final selected = Set<String>.from(state.selectedIds)..removeAll(lineageIds);
    emit(
      state.copyWith(
        selectedIds: selected,
        note: '',
      ),
    );
  }

  ForwardCandidate? _findCandidate(String userId) =>
      state.lineageSuggestions.where((c) => c.id == userId).firstOrNull ??
      state.candidates.where((c) => c.id == userId).firstOrNull;

  void setFilter(ForwardFilter filter) {
    emit(state.copyWith(activeFilter: filter));
  }

  void toggleSelection(String userId) {
    final selected = Set<String>.from(state.selectedIds);
    if (selected.contains(userId)) {
      selected.remove(userId);
    } else {
      selected.add(userId);
    }
    final notes = Map<String, String>.from(state.perRecipientNotes);
    final reasons = Map<String, List<String>>.from(state.recipientReasons);
    state.selectedIds.difference(selected).forEach((id) {
      notes.remove(id);
      reasons.remove(id);
    });
    emit(
      state.copyWith(
        selectedIds: selected,
        perRecipientNotes: notes,
        recipientReasons: reasons,
      ),
    );
  }

  void setRecipientReasons(String userId, List<String> slugs) {
    final next = Map<String, List<String>>.from(state.recipientReasons);
    if (slugs.isEmpty) {
      next.remove(userId);
    } else {
      next[userId] = slugs;
    }
    emit(state.copyWith(recipientReasons: next));
  }

  void setNote(String note) {
    emit(state.copyWith(note: note));
  }

  void setRecipientNote(String userId, String note) {
    final next = Map<String, String>.from(state.perRecipientNotes);
    if (note.trim().isEmpty) {
      next.remove(userId);
    } else {
      next[userId] = note;
    }
    emit(state.copyWith(perRecipientNotes: next));
  }

  void clearRecipientNote(String userId) {
    if (!state.perRecipientNotes.containsKey(userId)) return;
    final next = Map<String, String>.from(state.perRecipientNotes)
      ..remove(userId);
    emit(state.copyWith(perRecipientNotes: next));
  }

  void startEditForward(String recipientId) {
    final candidate = _findCandidate(recipientId);
    if (candidate == null) return;
    emit(
      state.copyWith(
        editingRecipientId: recipientId,
        editNote: candidate.myForwardNote ?? '',
        editReasons: null,
      ),
    );
  }

  void setEditNote(String note) => emit(state.copyWith(editNote: note));

  void setEditReasons(List<String> slugs) =>
      emit(state.copyWith(editReasons: slugs));

  void cancelEditForward() => emit(state.copyWith(editingRecipientId: null));

  Future<void> saveForwardEdit() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) return;
    final recipientId = state.editingRecipientId;
    if (recipientId == null) return;
    final edgeId = _findCandidate(recipientId)?.forwardEdgeId;
    if (edgeId == null) return;

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await forwardCase.updateForward(
        edgeId: edgeId,
        note: state.editNote.trim().isEmpty ? null : state.editNote.trim(),
        reasonSlugs: state.editReasons,
      );
      emit(state.copyWith(editingRecipientId: null));
      await _loadCandidates();
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<void> cancelForward(String recipientId) async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) return;
    final edgeId = _findCandidate(recipientId)?.forwardEdgeId;
    if (edgeId == null) return;

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final ok = await forwardCase.cancelForward(edgeId);
      if (!ok) {
        _emitSnackError(
          Exception(
            'Forward cannot be cancelled: already read or forwarded onward',
          ),
        );
        return;
      }
      await _loadCandidates();
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<List<ForwardInboundSource>> fetchInboundSources() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) return const [];
    return forwardCase.fetchInboundForwardSources(beaconId: state.beaconId);
  }

  Future<bool> forward({List<String>? attributionParentEdgeIds}) async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return false;
    }
    if (state.selectedIds.isEmpty && state.droppedPreselectedIds.isEmpty) {
      return false;
    }
    final beacon = state.beacon;
    if (beacon == null || beacon.status != BeaconStatus.open) {
      _emitSnackError(
        Exception('Forwarding is only available while the request is open'),
      );
      return false;
    }

    final todayUtc = _todayUtc();
    final allCandidates = [
      ...state.candidates,
      ...state.lineageSuggestions,
    ];
    final candidateById = {for (final c in allCandidates) c.id: c};
    final requestedRecipientIds = _stableRequestedRecipientOrder(
      droppedPreselectedIds: state.droppedPreselectedIds,
      selectedIds: state.selectedIds,
      candidates: state.candidates,
      lineageSuggestions: state.lineageSuggestions,
    );

    final localAvailabilitySkipped = <String>[];
    final recipientIdsToSend = <String>[];
    for (final id in requestedRecipientIds) {
      final candidate = candidateById[id];
      if (candidate == null ||
          candidate.profile.availability.blocksNewRequestsOn(todayUtc)) {
        localAvailabilitySkipped.add(id);
        continue;
      }
      recipientIdsToSend.add(id);
    }

    final ineligibleSelected = state.selectedIds
        .where(
          (id) {
            final candidate = candidateById[id];
            return candidate != null &&
                !candidate.profile.availability.blocksNewRequestsOn(todayUtc) &&
                !candidate.canForwardToOn(todayUtc);
          },
        )
        .toList();
    if (ineligibleSelected.isNotEmpty) {
      _emitSnackError(const IneligibleRecipientsException());
      return false;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    _suppressForwardChangeReload = true;
    try {
      if (recipientIdsToSend.isEmpty) {
        final outcome = _buildDeliveryOutcome(
          requestedRecipientIds: requestedRecipientIds,
          deliveredRecipientIds: const [],
          availabilitySkippedRecipientIds: requestedRecipientIds,
        );
        if (!isClosed) {
          emit(
            state.copyWith(
              lastDeliveryOutcome: outcome,
              status: const StateIsSuccess(),
            ),
          );
        }
        if (!embedded) {
          _emitDeliveryMessage(outcome);
          _emitNavigateBack(result: true);
        }
        return true;
      }

      final perNotes = <String, String>{};
      for (final id in recipientIdsToSend) {
        final personal = state.perRecipientNotes[id];
        if (personal != null && personal.trim().isNotEmpty) {
          perNotes[id] = personal.trim();
        }
      }
      final composedNote = state.note.trim();
      final bandByUserId = {
        for (final row in state.band) row.userId: row,
      };
      final recipientBandProvenance = <String, ({String? tier, bool isExploration})>{
        for (final id in recipientIdsToSend)
          if (bandByUserId[id] case final row?)
            id: (tier: row.rowTier?.name, isExploration: row.isExploration),
      };
      final result = await forwardCase.forwardBeacon(
        beaconId: state.beaconId,
        recipientIds: recipientIdsToSend,
        note: composedNote.isEmpty ? null : composedNote,
        perRecipientNotes: perNotes.isEmpty ? null : perNotes,
        context: state.context.isEmpty ? null : state.context,
        recipientReasons: state.recipientReasons.isEmpty
            ? null
            : state.recipientReasons,
        attributionParentEdgeIds: attributionParentEdgeIds,
        recipientBandProvenance: recipientBandProvenance.isEmpty
            ? null
            : recipientBandProvenance,
      );
      final availabilitySkippedRecipientIds = requestedRecipientIds
          .where(
            (id) =>
                localAvailabilitySkipped.contains(id) ||
                result.availabilitySkippedRecipientIds.contains(id),
          )
          .toList();
      final outcome = _buildDeliveryOutcome(
        requestedRecipientIds: requestedRecipientIds,
        deliveredRecipientIds: result.deliveredRecipientIds,
        availabilitySkippedRecipientIds: availabilitySkippedRecipientIds,
      );
      if (!isClosed) {
        emit(
          state.copyWith(
            lastDeliveryOutcome: outcome,
            status: const StateIsSuccess(),
          ),
        );
      }
      if (!embedded) {
        _emitDeliveryMessage(outcome);
        _emitNavigateBack(result: true);
      }
      return true;
    } catch (e) {
      if (embedded && !isClosed) {
        emit(
          state.copyWith(
            lastDeliveryOutcome: _buildDeliveryOutcome(
              requestedRecipientIds: requestedRecipientIds,
              deliveredRecipientIds: const [],
              availabilitySkippedRecipientIds: const [],
              failed: true,
            ),
            status: const StateIsSuccess(),
          ),
        );
      }
      _emitSnackError(e);
      return false;
    } finally {
      _suppressForwardChangeReload = false;
    }
  }
}
