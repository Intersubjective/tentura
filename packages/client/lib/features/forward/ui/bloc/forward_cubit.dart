import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';

import '../../data/repository/forward_repository.dart'
    show BeaconInvolvementData;
import '../../domain/use_case/forward_case.dart';
import '../../domain/entity/candidate_involvement.dart';
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
    @visibleForTesting bool debugSkipInitialLoad = false,
  }) : _forwardCase = forwardCase ??
           (debugSkipInitialLoad ? null : GetIt.I<ForwardCase>()),
       super(ForwardState(beaconId: beaconId, context: context)) {
    if (!debugSkipInitialLoad) {
      unawaited(_loadCandidates());
    }
  }

  final ForwardCase? _forwardCase;

  Future<void> _loadCandidates() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final results = await Future.wait([
        forwardCase.fetchForwardCandidates(context: state.context),
        forwardCase.fetchBeaconInvolvement(beaconId: state.beaconId),
      ]);
      final profiles = results[0] as Iterable<Profile>;
      final involvement = results[1] as BeaconInvolvementData;
      final myId = await forwardCase.getCurrentAccountId();

      var candidates = profiles
          .where((p) => p.id != myId)
          .map(
            (p) => ForwardCandidate(
              profile: p,
              involvement: _computeInvolvement(p.id, involvement),
              myForwardNote:
                  involvement.myForwardedRecipientNotes[p.id],
            ),
          )
          .toList()
        ..sort((a, b) => b.mrScore.compareTo(a.mrScore));

      final ids = candidates.map((c) => c.id).toList();
      if (ids.isNotEmpty) {
        try {
          final topCaps =
              await forwardCase.fetchTopCapabilitiesForCandidates(ids);
          candidates = candidates
              .map((c) => c.copyWith(
                    topCapabilities: topCaps[c.id] ?? [],
                  ))
              .toList();
        } catch (_) {
          // Non-critical: capability hints are best-effort.
        }
      }

      emit(
        state.copyWith(
          beacon: involvement.beacon,
          candidates: candidates,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  static CandidateInvolvement _computeInvolvement(
    String userId,
    BeaconInvolvementData inv,
  ) {
    if (userId == inv.beacon.author.id) {
      return CandidateInvolvement.author;
    }
    if (inv.committedIds.contains(userId)) {
      return CandidateInvolvement.committed;
    }
    if (inv.withdrawnIds.contains(userId)) {
      return CandidateInvolvement.withdrawn;
    }
    if (inv.myForwardedRecipientNotes.containsKey(userId)) {
      return CandidateInvolvement.forwardedByMe;
    }
    if (inv.rejectedIds.contains(userId)) {
      return CandidateInvolvement.declined;
    }
    if (inv.onwardForwarderIds.contains(userId)) {
      return CandidateInvolvement.forwarded;
    }
    if (inv.watchingIds.contains(userId)) {
      return CandidateInvolvement.watching;
    }
    if (inv.forwardedToIds.contains(userId)) {
      return CandidateInvolvement.forwarded;
    }
    return CandidateInvolvement.unseen;
  }

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

  Future<void> forward() async {
    final forwardCase = _forwardCase;
    if (forwardCase == null) {
      return;
    }
    if (state.selectedIds.isEmpty) return;

    final selectedCandidates = state.candidates
        .where((c) => state.selectedIds.contains(c.id))
        .toList();

    final ineligible = selectedCandidates.where((c) => !c.canForwardTo).toList();
    if (ineligible.isNotEmpty) {
      emit(state.copyWith(status: StateHasError(const IneligibleRecipientsException())));
      emit(state.copyWith(status: const StateIsSuccess()));
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
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
