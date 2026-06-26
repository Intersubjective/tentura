import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';
import 'package:meta/meta.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/use_case/forward_case.dart';
import '../../domain/entity/forward_candidate.dart';
import '../../domain/exception.dart';
import 'forward_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'forward_state.dart';

class ForwardCubit extends Cubit<ForwardState> {
  ForwardCubit({
    required String beaconId,
    String context = '',
    ForwardCase? forwardCase,
    UiEffectPort? effects,
    @visibleForTesting bool debugSkipInitialLoad = false,
  }) : _forwardCase =
           forwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<ForwardCase>()),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(ForwardState(beaconId: beaconId, context: context)) {
    if (!debugSkipInitialLoad) {
      unawaited(_loadCandidates());
    }
    _subscribeLiveUpdates();
  }

  final ForwardCase? _forwardCase;

  final UiEffectPort _effects;

  StreamSubscription<String>? _forwardCompletedSub;

  StreamSubscription<void>? _contactChangesSub;

  void _subscribeLiveUpdates() {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    _forwardCompletedSub = forwardCase.forwardCompleted
        .where((id) => id == state.beaconId)
        .listen((_) {
          if (!isClosed) {
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
  }

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  void _emitNavigateBack({Object? result}) {
    _effects.emit(NavigateBack(result: result));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  String? _loadMemoKey;

  Future<void> _loadCandidates({bool forceReload = false}) async {
    final forwardCase = _forwardCase;
    if (forwardCase == null || isClosed) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
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

      // Never pre-select recipients: forwarding is an explicit send action, and
      // auto-checking server-suggested people risks mis-forwarding (QA Jun-26).
      // Preserve the user's own selection across live reloads, pruning anyone no
      // longer present in the candidate or lineage lists.
      final availableIds = {
        for (final c in load.candidates) c.id,
        for (final c in load.lineageSuggestions) c.id,
      };
      final preservedSelection = state.selectedIds.intersection(availableIds);

      emit(
        state.copyWith(
          beacon: load.beacon,
          candidates: load.candidates,
          lineageSuggestions: load.lineageSuggestions,
          selectedIds: preservedSelection,
          note: load.suggestedNote,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  @override
  Future<void> close() async {
    await _forwardCompletedSub?.cancel();
    await _contactChangesSub?.cancel();
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
        editReasons: const [],
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
        reasonSlugs: state.editReasons.isEmpty ? null : state.editReasons,
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

  Future<void> forward() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    if (state.selectedIds.isEmpty) return;
    final beacon = state.beacon;
    if (beacon == null || beacon.status != BeaconStatus.open) {
      _emitSnackError(
        Exception('Forwarding is only available while the beacon is open'),
      );
      return;
    }

    final allCandidates = [
      ...state.candidates,
      ...state.lineageSuggestions,
    ];
    final selectedCandidates = allCandidates
        .where((c) => state.selectedIds.contains(c.id))
        .toList();

    final ineligible = selectedCandidates
        .where((c) => !c.canForwardTo)
        .toList();
    if (ineligible.isNotEmpty) {
      _emitSnackError(const IneligibleRecipientsException());
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final perNotes = <String, String>{};
      for (final id in state.selectedIds) {
        final personal = state.perRecipientNotes[id];
        if (personal != null && personal.trim().isNotEmpty) {
          perNotes[id] = personal.trim();
        }
      }
      final composedNote = state.note.trim();
      await forwardCase.forwardBeacon(
        beaconId: state.beaconId,
        recipientIds: state.selectedIds.toList(),
        note: composedNote.isEmpty ? null : composedNote,
        perRecipientNotes: perNotes.isEmpty ? null : perNotes,
        context: state.context.isEmpty ? null : state.context,
        recipientReasons: state.recipientReasons.isEmpty
            ? null
            : state.recipientReasons,
      );
      _emitNavigateBack(result: true);
    } catch (e) {
      _emitSnackError(e);
    }
  }
}
