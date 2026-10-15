import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/post_bud_invite_outcome.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/parallel_wait_failure.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

part 'beacon_author_invites_state.dart';
part 'beacon_author_invites_cubit.freezed.dart';

/// The author's invites section on a budded Request's People tab (plan D4):
/// invites with their status and note, withdraw, and «Позвать» on the
/// snapshot observers (`beaconAuthorInviteCreate`).
///
/// Only the Request author mounts it; the server answers anyone else with
/// empty lists anyway.
final class BeaconAuthorInvitesCubit extends Cubit<BeaconAuthorInvitesState> {
  BeaconAuthorInvitesCubit({
    required String beaconId,
    AuthorInviteCase? authorInviteCase,
    AttentionActorProfilesCase? actorProfiles,
    UiEffectPort? effects,
  }) : _invites = authorInviteCase ?? GetIt.I<AuthorInviteCase>(),
       _profiles = actorProfiles ?? GetIt.I<AttentionActorProfilesCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(BeaconAuthorInvitesState(beaconId: beaconId));

  final AuthorInviteCase _invites;
  final AttentionActorProfilesCase _profiles;
  final UiEffectPort _effects;

  Future<void> load() async {
    try {
      final (invites, observerIds) = await (
        _invites.beaconInvites(state.beaconId),
        _invites.budObservers(state.beaconId),
      ).wait;
      final ids = {
        ...observerIds,
        for (final i in invites) ?i.inviteeId,
      };
      final profiles = ids.isEmpty
          ? const <String, Profile>{}
          : await _profiles.resolve(ids);
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          invites: invites,
          observerIds: observerIds,
          profiles: {...state.profiles, ...profiles},
        ),
      );
    } on Object catch (error) {
      if (isClosed) return;
      emit(state.copyWith(status: const StateIsSuccess()));
      _effects.emit(ShowError(unwrapRetryLater(error)));
    }
  }

  /// «Позвать»: a later invite of a snapshot observer. An outcome other
  /// than invited is reported through [BeaconAuthorInvitesState.notInvited].
  Future<void> invite(String userId, {String? note}) => _busy(userId, () async {
    final result = await _invites.create(
      beaconId: state.beaconId,
      userId: userId,
      note: note,
    );
    if (result.outcome != PostBudInviteOutcome.invited && !isClosed) {
      emit(
        state.copyWith(
          notInvited: BeaconAuthorInviteRefusal(
            userId: userId,
            outcome: result.outcome,
            seq: (state.notInvited?.seq ?? 0) + 1,
          ),
        ),
      );
    }
  });

  /// «Отозвать приглашение» on a pending invite.
  Future<void> withdraw(String inviteId) {
    final userId = state.invites
        .where((i) => i.id == inviteId)
        .map((i) => i.inviteeId)
        .firstOrNull;
    return _busy(userId ?? inviteId, () => _invites.withdraw(inviteId));
  }

  Future<void> _busy(String userId, Future<void> Function() send) async {
    if (state.busyUserIds.contains(userId)) return;
    emit(state.copyWith(busyUserIds: {...state.busyUserIds, userId}));
    try {
      await send();
    } on Object catch (error) {
      if (!isClosed) _effects.emit(ShowError(error));
    }
    if (isClosed) return;
    await load();
    if (isClosed) return;
    emit(
      state.copyWith(busyUserIds: {...state.busyUserIds}..remove(userId)),
    );
  }
}
