import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

/// The viewer's own pending author invite on the Request they are looking
/// at (#664), with the inviter's profile once it has loaded.
@immutable
final class BeaconMyInviteState {
  const BeaconMyInviteState({this.invite, this.inviter, this.busy = false});

  /// Null when the viewer has no pending invite on this Request.
  final PendingAuthorInvite? invite;
  final Profile? inviter;

  /// An accept or decline is on its way.
  final bool busy;
}

/// The invitation banner on the Request page (#664): the same «Принять» /
/// «Не смогу» as the Activity invite card, for an invitee who opened the
/// Request itself (e.g. from the Post's bud notice).
///
/// Reads `myPendingAuthorInvites` and keeps the one for [beaconId].
final class BeaconMyInviteCubit extends Cubit<BeaconMyInviteState> {
  BeaconMyInviteCubit({
    required this.beaconId,
    AuthorInviteCase? authorInviteCase,
    AttentionActorProfilesCase? actorProfiles,
    UiEffectPort? effects,
    this.onAnswered,
    this.onDeclineNote,
  }) : _invites = authorInviteCase ?? GetIt.I<AuthorInviteCase>(),
       _profiles =
           actorProfiles ??
           (GetIt.I.isRegistered<AttentionActorProfilesCase>()
               ? GetIt.I<AttentionActorProfilesCase>()
               : null),
       _effects =
           effects ??
           (GetIt.I.isRegistered<UiEffectPort>()
               ? GetIt.I<UiEffectPort>()
               : null),
       super(const BeaconMyInviteState());

  final String beaconId;

  /// Called once the server took the answer: the Request page reloads, so
  /// an accepted invitee lands inside at once.
  final Future<void> Function()? onAnswered;

  /// Records the rejection dialog's optional note after a decline (the way
  /// «Не могу помочь» does); best-effort.
  final Future<void> Function(String message)? onDeclineNote;

  final AuthorInviteCase _invites;
  final AttentionActorProfilesCase? _profiles;
  final UiEffectPort? _effects;

  Future<void> load() async {
    try {
      final pending = await _invites.myPending();
      final invite = pending.where((i) => i.beaconId == beaconId).firstOrNull;
      if (isClosed) return;
      emit(BeaconMyInviteState(invite: invite, inviter: state.inviter));
      if (invite == null) return;
      final profiles = await _profiles?.resolve({invite.inviterId});
      final inviter = profiles?[invite.inviterId];
      if (isClosed || inviter == null || state.invite?.id != invite.id) return;
      emit(
        BeaconMyInviteState(
          invite: state.invite,
          inviter: inviter,
          busy: state.busy,
        ),
      );
    } on Object {
      // The banner is an extra on the page: a failed read shows nothing.
    }
  }

  /// «Принять»: the viewer's own confirmation; the author already asked.
  Future<void> accept() => _answer(_invites.accept);

  /// «Не смогу», with the rejection dialog's optional [message].
  Future<void> decline({String message = ''}) =>
      _answer(_invites.decline, note: message);

  Future<void> _answer(
    Future<Object?> Function(String inviteId) send, {
    String note = '',
  }) async {
    final invite = state.invite;
    if (invite == null || state.busy) return;
    emit(
      BeaconMyInviteState(invite: invite, inviter: state.inviter, busy: true),
    );
    try {
      await send(invite.id);
    } on Object catch (error) {
      if (isClosed) return;
      _effects?.emit(ShowError(error));
      emit(BeaconMyInviteState(invite: invite, inviter: state.inviter));
      // Expired, withdrawn, already answered elsewhere: show what is left.
      await load();
      return;
    }
    if (isClosed) return;
    emit(BeaconMyInviteState(inviter: state.inviter));
    final noteSink = onDeclineNote;
    if (note.isNotEmpty && noteSink != null) {
      try {
        await noteSink(note);
      } on Object {
        // The decline itself succeeded; the note is best-effort.
      }
    }
    await onAnswered?.call();
  }
}
