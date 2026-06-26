import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import '../../data/repository/invitation_repository.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/data/service/web_redirect.dart';
import 'package:tentura/features/home/ui/bloc/post_join_navigation_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import '../../domain/entity/invite_preview.dart';
import '../../domain/invite_code.dart';
import '../../domain/port/invitation_accept_port.dart';
import '../../domain/exception.dart';
import '../message/accept_invite_messages.dart';
import 'accept_invite_state.dart';

export 'accept_invite_state.dart';

@injectable
class AcceptInviteCubit extends Cubit<AcceptInviteState> {
  @factoryMethod
  AcceptInviteCubit(
    InvitationRepository repository,
    UiEffectPort effects,
    PostJoinNavigationCubit postJoinNavigation,
  ) : _repository = repository,
      _effects = effects,
      _postJoinNavigation = postJoinNavigation,
      super(const AcceptInviteState());

  @visibleForTesting
  AcceptInviteCubit.withPort(
    InvitationAcceptPort repository, {
    UiEffectPort? effects,
    PostJoinNavigationCubit? postJoinNavigation,
  }) : _repository = repository,
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       _postJoinNavigation =
           postJoinNavigation ?? GetIt.I<PostJoinNavigationCubit>(),
       super(const AcceptInviteState());

  final InvitationAcceptPort _repository;

  final UiEffectPort _effects;

  final PostJoinNavigationCubit _postJoinNavigation;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> start(String rawCode) async {
    final hadTrailingDash = inviteCodeHadTrailingDash(rawCode);
    final code = normalizeInviteCode(rawCode);
    emit(AcceptInviteState(code: code));
    if (!isValidInviteCode(code)) {
      _finishWithMessage(
        hadTrailingDash
            ? const InviteTrailingDashHintMessage()
            : const InviteInvalidCodeMessage(),
      );
      return;
    }
    try {
      final preview = await _repository.fetchInvitePreview(code);
      await _handlePreview(code, preview);
    } on InvitationAuthLost {
      _bounceUnauthenticated(code);
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<void> confirmAccept() async {
    final code = state.code;
    if (code.isEmpty) {
      _goHome();
      return;
    }
    final inviter = state.pendingInviter;
    final beacon = state.pendingBeacon;
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _repository.acceptExistingInvite(code);
      if (beacon != null && beacon.id.isNotEmpty) {
        _postJoinNavigation.setFromBeaconInvite(
          beaconId: beacon.id,
          beaconTitle: beacon.title,
          inviterName: inviter?.displayName ?? '',
          showSnackbar: false,
        );
        _finishWithMessage(
          BeaconInviteAcceptedMessage(
            inviterName: inviter?.displayName ?? '',
            beaconId: beacon.id,
            beaconTitle: beacon.title,
          ),
          navigateToInbox: true,
        );
      } else {
        _finishWithMessage(const InviteAcceptedMessage());
      }
    } on InvitationNoLongerValid {
      _finishWithMessage(const InviteNoLongerValidMessage());
    } on InvitationSelfOrInvalid {
      _finishWithMessage(const InviteOwnInviteMessage());
    } on InvitationAuthLost {
      _bounceUnauthenticated(code);
    } catch (e) {
      _emitSnackError(e);
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
            pendingBeacon: preview.beacon,
          ),
        );
    }
  }

  void _finishWithMessage(
    LocalizableMessage message, {
    bool navigateToInbox = false,
  }) {
    _effects.emit(ShowMessage(message));
    _effects.emit(
      NavigateReplace(
        navigateToInbox
            ? NavigateReplaceTarget.homeInboxTab
            : NavigateReplaceTarget.home,
      ),
    );
    emit(
      state.copyWith(
        status: const StateIsSuccess(),
        pendingInviter: null,
        pendingBeacon: null,
      ),
    );
  }

  void _goHome() {
    _effects.emit(const NavigateReplace(NavigateReplaceTarget.home));
    emit(
      state.copyWith(
        status: const StateIsSuccess(),
        pendingInviter: null,
        pendingBeacon: null,
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
