import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../../invitation/data/repository/invitation_repository.dart';
import '../../../invitation/domain/entity/invite_preview.dart';
import '../../../invitation/domain/invite_code.dart';
import '../../../invitation/domain/port/invitation_accept_port.dart';
import '../../../invitation/ui/message/accept_invite_messages.dart';

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
  }) => RegisterInviteState(
    preview: preview ?? this.preview,
    status: status ?? this.status,
  );
}

/// Loads invite preview for the native register screen (beacon post-join wiring).
@injectable
class RegisterInviteCubit extends Cubit<RegisterInviteState> {
  RegisterInviteCubit(
    InvitationRepository repository,
    UiEffectPort effects,
  ) : _repository = repository,
      _effects = effects,
      super(const RegisterInviteState());

  @visibleForTesting
  RegisterInviteCubit.withPort(
    InvitationAcceptPort repository, {
    UiEffectPort? effects,
  }) : _repository = repository,
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const RegisterInviteState());

  final InvitationAcceptPort _repository;

  final UiEffectPort _effects;

  Future<void> load(String rawCode) async {
    final formatMessage = inviteCodeFormatMessage(rawCode);
    if (formatMessage != null) {
      _effects.emit(ShowMessage(formatMessage));
      return;
    }
    final code = normalizeInviteCode(rawCode);
    if (code.isEmpty) {
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
