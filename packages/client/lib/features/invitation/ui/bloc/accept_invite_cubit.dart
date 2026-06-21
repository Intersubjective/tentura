import 'package:injectable/injectable.dart';

import '../../data/repository/invitation_repository.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/data/service/web_redirect.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import '../../domain/entity/invite_preview.dart';
import '../../domain/port/invitation_accept_port.dart';
import '../../domain/exception.dart';
import '../message/accept_invite_messages.dart';
import 'accept_invite_state.dart';

export 'accept_invite_state.dart';

@injectable
class AcceptInviteCubit extends Cubit<AcceptInviteState> {
  @factoryMethod
  AcceptInviteCubit(InvitationRepository repository)
    : _repository = repository,
      super(const AcceptInviteState());

  @visibleForTesting
  AcceptInviteCubit.withPort(InvitationAcceptPort repository)
    : _repository = repository,
      super(const AcceptInviteState());

  final InvitationAcceptPort _repository;

  Future<void> start(String rawCode) async {
    final code = rawCode.trim();
    emit(AcceptInviteState(code: code));
    if (!kInvitationCodeRegExp.hasMatch(code)) {
      _finishWithMessage(const InviteInvalidCodeMessage());
      return;
    }
    try {
      final preview = await _repository.fetchInvitePreview(code);
      await _handlePreview(code, preview);
    } on InvitationAuthLost {
      _bounceUnauthenticated(code);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> confirmAccept() async {
    final code = state.code;
    if (code.isEmpty) {
      _goHome();
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading, pendingInviter: null));
    try {
      await _repository.acceptExistingInvite(code);
      _finishWithMessage(const InviteAcceptedMessage());
    } on InvitationNoLongerValid {
      _finishWithMessage(const InviteNoLongerValidMessage());
    } on InvitationSelfOrInvalid {
      _finishWithMessage(const InviteOwnInviteMessage());
    } on InvitationAuthLost {
      _bounceUnauthenticated(code);
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void cancelAccept() => _goHome();

  Future<void> _handlePreview(String code, InvitePreview preview) async {
    if (preview.codeStatus != InviteCodeStatus.available) {
      _finishWithMessage(const InviteNoLongerValidMessage());
      return;
    }
    switch (preview.callerStatus) {
      case InviteCallerStatus.isInviter:
        _finishWithMessage(const InviteOwnInviteMessage());
      case InviteCallerStatus.alreadyFriends:
        _finishWithMessage(const InviteAlreadyFriendsMessage());
      case InviteCallerStatus.anonymous:
        _bounceUnauthenticated(code);
      case InviteCallerStatus.existingUser:
        final inviter = preview.inviter;
        if (inviter == null || inviter.id.isEmpty) {
          _finishWithMessage(const InviteNoLongerValidMessage());
          return;
        }
        emit(
          state.copyWith(
            status: StateStatus.isSuccess,
            pendingInviter: Profile(
              id: inviter.id,
              displayName: inviter.displayName,
            ),
          ),
        );
    }
  }

  void _finishWithMessage(LocalizableMessage message) {
    emit(
      state.copyWith(
        status: StateIsMessaging(message),
        pendingInviter: null,
      ),
    );
  }

  void _goHome() {
    emit(
      state.copyWith(
        status: const StateIsNavigating(kPathHome),
        pendingInviter: null,
      ),
    );
  }

  void _bounceUnauthenticated(String code) {
    if (kIsWeb && goToLanding(invitePath: '/invite/$code')) {
      return;
    }
    emit(
      state.copyWith(
        status: StateIsNavigating('$kPathSignUp/$code'),
        pendingInviter: null,
      ),
    );
  }
}
