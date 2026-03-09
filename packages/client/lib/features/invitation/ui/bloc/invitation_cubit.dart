// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods
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
      super(const InvitationState());

  final InvitationRepository _invitationRepository;

  Future<void> fetch({bool clear = true}) async {
    if (state.isLoading || state.hasReachedMax) return;

    if (clear) {
      emit(
        state.copyWith(
          invitations: [],
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
      state.invitations
        ..addAll(invitations)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(
        state.copyWith(
          status: StateStatus.isSuccess,
          hasReachedMax: invitations.length < kFetchListOffset,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<InvitationEntity?> createInvitation() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final invitation = await _invitationRepository.create();
      state.invitations.add(invitation);
      emit(state.copyWith(status: StateStatus.isSuccess));
      return invitation;
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
    return null;
  }

  Future<void> deleteInvitationById(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _invitationRepository.deleteById(id);
      state.invitations.removeWhere((e) => e.id == id);
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
