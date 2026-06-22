import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
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
  }) : _forwardCase = forwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<ForwardCase>()),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(ForwardState(beaconId: beaconId, context: context)) {
    if (!debugSkipInitialLoad) {
      unawaited(_loadCandidates());
    }
  }

  final ForwardCase? _forwardCase;

  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  String? _loadMemoKey;

  Future<void> _loadCandidates() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final myId = await forwardCase.getCurrentAccountId();
      final load = await forwardCase.loadForwardCandidates(
        beaconId: state.beaconId,
        context: state.context,
      );
      final memoKey =
          '$myId|${state.beaconId}|${load.beacon.lineageParentBeaconId ?? ''}';
      if (_loadMemoKey == memoKey && state.candidates.isNotEmpty) {
        emit(state.copyWith(status: const StateIsSuccess()));
        return;
      }
      _loadMemoKey = memoKey;

      emit(
        state.copyWith(
          beacon: load.beacon,
          candidates: load.candidates,
          lineageSuggestions: load.lineageSuggestions,
          selectedIds: load.autoSelectIds,
          note: load.suggestedNote,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
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
    final next = Map<String, String>.from(state.perRecipientNotes)..remove(userId);
    emit(state.copyWith(perRecipientNotes: next));
  }

  void startEditForward(String recipientId) {
    final candidate = _findCandidate(recipientId);
    if (candidate == null) return;
    emit(state.copyWith(
      editingRecipientId: recipientId,
      editNote: candidate.myForwardNote ?? '',
      editReasons: const [],
    ));
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
          Exception('Forward cannot be cancelled: already read or forwarded onward'),
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
    if (beacon == null || beacon.lifecycle != BeaconLifecycle.open) {
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

    final ineligible = selectedCandidates.where((c) => !c.canForwardTo).toList();
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
      _effects.emit(const NavigateBack(result: true));
      emit(state.copyWith(status: const StateIsSuccess()));
    } catch (e) {
      _emitSnackError(e);
    }
  }
}
