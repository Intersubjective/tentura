import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../../invitation/data/repository/invitation_repository.dart';
import '../../../invitation/domain/entity/invite_preview.dart';
import '../../../invitation/domain/port/invitation_accept_port.dart';

class RegisterInviteState {
  const RegisterInviteState({
    this.preview,
    this.status = const StateIsSuccess(),
  });

  final InvitePreview? preview;
  final StateStatus status;

  RegisterInviteState copyWith({
    InvitePreview? preview,
    StateStatus? status,
  }) =>
      RegisterInviteState(
        preview: preview ?? this.preview,
        status: status ?? this.status,
      );
}

/// Loads invite preview for the native register screen (beacon post-join wiring).
@injectable
class RegisterInviteCubit extends Cubit<RegisterInviteState> {
  RegisterInviteCubit(InvitationRepository repository)
      : _repository = repository,
        super(const RegisterInviteState());

  final InvitationAcceptPort _repository;

  Future<void> load(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty || !kInvitationCodeRegExp.hasMatch(code)) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final preview = await _repository.fetchInvitePreview(code);
      if (!isClosed) {
        emit(
          state.copyWith(
            status: const StateIsSuccess(),
            preview: preview,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess(), preview: null));
      }
    }
  }
}
