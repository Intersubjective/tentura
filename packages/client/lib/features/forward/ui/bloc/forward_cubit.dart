import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';

import '../../data/repository/forward_repository.dart';
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
      final friends = await _friendsRepository.fetch();
      final rejected = await _forwardRepository.fetchRejectedUserIds(
        beaconId: state.beaconId,
      );
      emit(
        state.copyWith(
          candidates: friends.toList(),
          rejectedUserIds: rejected,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void toggleSelection(String userId) {
    final selected = Set<String>.from(state.selectedIds);
    if (selected.contains(userId)) {
      selected.remove(userId);
    } else {
      selected.add(userId);
    }
    emit(state.copyWith(selectedIds: selected));
  }

  void setSearchQuery(String query) {
    emit(state.copyWith(searchQuery: query));
  }

  void setNote(String note) {
    emit(state.copyWith(note: note));
  }

  Future<void> forward() async {
    if (state.selectedIds.isEmpty) return;

    final ineligible = state.candidates
        .where(
          (p) => state.selectedIds.contains(p.id) && !p.isSeeingMe,
        )
        .toList();
    if (ineligible.isNotEmpty) {
      emit(state.copyWith(status: StateHasError(const IneligibleRecipientsException())));
      emit(state.copyWith(status: const StateIsSuccess()));
      return;
    }

    final declined = state.candidates
        .where(
          (p) =>
              state.selectedIds.contains(p.id) &&
              state.rejectedUserIds.contains(p.id),
        )
        .toList();
    if (declined.isNotEmpty) {
      emit(state.copyWith(status: StateHasError(const IneligibleRecipientsException())));
      emit(state.copyWith(status: const StateIsSuccess()));
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _forwardRepository.forwardBeacon(
        beaconId: state.beaconId,
        recipientIds: state.selectedIds.toList(),
        note: state.note.isEmpty ? null : state.note,
        context: state.context.isEmpty ? null : state.context,
      );
      emit(state.copyWith(status: const StateIsNavigating(kPathBack)));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
