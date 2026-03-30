import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';

import '../../data/repository/forward_repository.dart';
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
    ForwardRepository? forwardRepository,
    FriendsRemoteRepository? friendsRepository,
  }) : _forwardRepository =
           forwardRepository ?? GetIt.I<ForwardRepository>(),
       _friendsRepository =
           friendsRepository ?? GetIt.I<FriendsRemoteRepository>(),
       super(ForwardState(beaconId: beaconId, context: context)) {
    unawaited(_loadCandidates());
  }

  final ForwardRepository _forwardRepository;
  final FriendsRemoteRepository _friendsRepository;

  Future<void> _loadCandidates() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final results = await Future.wait([
        _friendsRepository.fetch(),
        _forwardRepository.fetchBeaconInvolvement(beaconId: state.beaconId),
      ]);
      final friends = results[0] as Iterable<Profile>;
      final involvement = results[1] as BeaconInvolvementData;

      final candidates = friends
          .map(
            (p) => ForwardCandidate(
              profile: p,
              involvement: _computeInvolvement(p.id, involvement),
            ),
          )
          .toList()
        ..sort((a, b) => b.mrScore.compareTo(a.mrScore));

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
    if (inv.rejectedIds.contains(userId)) {
      return CandidateInvolvement.declined;
    }
    if (inv.committedIds.contains(userId)) {
      return CandidateInvolvement.committed;
    }
    if (inv.withdrawnIds.contains(userId)) {
      return CandidateInvolvement.withdrawn;
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
    state.selectedIds.difference(selected).forEach(notes.remove);
    emit(state.copyWith(selectedIds: selected, perRecipientNotes: notes));
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
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
      await _forwardRepository.forwardBeacon(
        beaconId: state.beaconId,
        recipientIds: state.selectedIds.toList(),
        note: state.note.isEmpty ? null : state.note,
        perRecipientNotes: perNotes.isEmpty ? null : perNotes,
        context: state.context.isEmpty ? null : state.context,
      );
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
