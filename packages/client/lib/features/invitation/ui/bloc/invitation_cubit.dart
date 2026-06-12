// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods
import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/repository/invitation_repository.dart';
import 'invitation_state.dart';

export 'invitation_state.dart';

class InvitationCubit extends Cubit<InvitationState> {
  InvitationCubit({InvitationRepository? invitationRepository})
    : _invitationRepository =
          invitationRepository ?? GetIt.I<InvitationRepository>(),
      super(const InvitationState()) {
    _repoChanges = _invitationRepository.changes.listen((_) {
      unawaited(fetch());
    });
  }

  final InvitationRepository _invitationRepository;

  StreamSubscription<void>? _repoChanges;

  Future<void> fetch({bool clear = true}) async {
    if (state.isLoading) {
      return;
    }
    if (!clear && state.hasReachedMax) {
      return;
    }

    if (clear) {
      emit(
        state.copyWith(
          invitations: <InvitationEntity>[],
          hasReachedMax: false,
          status: StateStatus.isLoading,
        ),
      );
    } else {
      emit(state.copyWith(status: StateStatus.isLoading));
    }

    try {
      final invitations = await _invitationRepository.fetchMine(
        offset: state.invitations.length,
      );
      final next = <InvitationEntity>[
        ...state.invitations,
        ...invitations,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(
        state.copyWith(
          invitations: next,
          status: StateStatus.isSuccess,
          hasReachedMax: invitations.length < kFetchListOffset,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<InvitationEntity?> createInvitation({
    required String addresseeName,
    String? beaconId,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final invitation = await _invitationRepository.create(
        addresseeName: addresseeName,
        beaconId: beaconId,
      );
      final next = <InvitationEntity>[
        ...state.invitations,
        invitation,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(state.copyWith(invitations: next, status: StateStatus.isSuccess));
      return invitation;
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
    return null;
  }

  Future<void> updateInvitation({
    required String id,
    required String addresseeName,
  }) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final updated = await _invitationRepository.update(
        id: id,
        addresseeName: addresseeName,
      );
      final next = [
        for (final e in state.invitations) e.id == id ? updated : e,
      ];
      emit(state.copyWith(invitations: next, status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> deleteInvitationById(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _invitationRepository.deleteById(id);
      final next = state.invitations.where((e) => e.id != id).toList();
      emit(state.copyWith(invitations: next, status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  @override
  Future<void> close() async {
    await _repoChanges?.cancel();
    return super.close();
  }
}
