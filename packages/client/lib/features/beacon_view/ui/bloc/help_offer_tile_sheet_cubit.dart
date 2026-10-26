import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';
import 'package:tentura/features/beacon_view/ui/message/help_offer_messages.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

part 'help_offer_tile_sheet_state.dart';
part 'help_offer_tile_sheet_cubit.freezed.dart';

class HelpOfferTileSheetCubit extends Cubit<HelpOfferTileSheetState> {
  HelpOfferTileSheetCubit({
    required String beaconId,
    required String offerUserId,
    required Profile myProfile,
    Beacon? initialBeacon,
    BeaconViewCase? beaconViewCase,
    UiEffectPort? effects,
  }) : _case = beaconViewCase ?? GetIt.I<BeaconViewCase>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         HelpOfferTileSheetState(
           beaconId: beaconId,
           offerUserId: offerUserId,
           myProfile: myProfile,
           beacon: initialBeacon ?? Beacon.empty.copyWith(id: beaconId),
         ),
       );

  final BeaconViewCase _case;
  final UiEffectPort _effects;

  Future<void> load() async {
    emit(state.copyWith(status: const StateIsLoading(), loadError: null));
    try {
      final beacon = await _case.fetchBeaconById(state.beaconId);
      final rows = await _case.fetchHelpOffersWithCoordination(
        beaconId: state.beaconId,
      );
      final participants = await _case.fetchRoomParticipants(state.beaconId);
      final offers = timelineHelpOffersFromRemote(rows);
      TimelineHelpOffer? offer;
      for (final o in offers) {
        if (o.user.id == state.offerUserId) {
          offer = o;
          break;
        }
      }
      BeaconParticipant? participant;
      for (final p in participants) {
        if (p.userId == state.offerUserId) {
          participant = p;
          break;
        }
      }
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          beacon: beacon,
          offer: offer,
          participant: participant,
          roomParticipants: participants,
          loadError: null,
        ),
      );
      if (state.isAuthorOrSteward) {
        try {
          await _case.markPeopleSeen(state.beaconId);
        } catch (_) {}
      }
    } catch (e) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: const StateIsSuccess(),
          loadError: e,
        ),
      );
      _effects.emit(ShowError(e));
    }
  }

  /// Accept and decline for an ordinary offer.
  bool get canManageOffer =>
      state.beacon.status.isOpenFamily &&
      _canActOnOtherOffer &&
      !state.offer!.isBackup;

  /// A pending backup offer is answered with «Keep as standby» or «Decline»
  /// instead (#596); it is never admitted from the sheet.
  bool get canAnswerBackupOffer =>
      state.beacon.status.isOpenFamily &&
      _canActOnOtherOffer &&
      state.offer!.isBackup &&
      state.participant?.roomAccess != RoomAccessBits.admitted &&
      state.offer!.stakeState != CommitmentStakeState.acknowledged;

  bool get canDeclineOffer => canManageOffer || canAnswerBackupOffer;

  /// Author may end a helper's participation in every non-final status,
  /// Wrapping up included (#489); admitting offers stays open-only.
  bool get canEndParticipation {
    final offer = state.offer;
    if (offer == null || offer.isWithdrawn) return false;
    // The sheet alone leaves backup offers out; the People tab shows End
    // participation for an admitted backup helper too.
    if (offer.isBackup) return false;
    final beacon = state.beacon;
    return beacon.canEndParticipationOf(
      targetIsAuthor: offer.user.id == beacon.author.id,
      targetIsViewer: offer.user.id == state.myProfile.id,
      viewerIsAuthorOrSteward: state.isAuthorOrSteward,
    );
  }

  bool get _canActOnOtherOffer {
    final offer = state.offer;
    if (offer == null || offer.isWithdrawn) return false;
    final beacon = state.beacon;
    if (offer.user.id == beacon.author.id) return false;
    if (offer.user.id == state.myProfile.id) return false;
    return state.isAuthorOrSteward;
  }

  Future<bool> accept() async {
    if (!canManageOffer) return false;
    try {
      await _case.acceptHelpOffer(
        beaconId: state.beaconId,
        offerUserId: state.offerUserId,
      );
      // #734: the sheet closes; say what happened.
      _effects.emit(ShowMessage(HelpOfferAcceptedMessage(_offererName)));
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }

  Future<bool> decline({required String reason}) async {
    if (!canDeclineOffer) return false;
    try {
      await _case.declineHelpOffer(
        beaconId: state.beaconId,
        offerUserId: state.offerUserId,
        reason: reason,
      );
      _effects.emit(ShowMessage(HelpOfferDeclinedMessage(_offererName)));
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }

  String get _offererName => state.offer?.user.shownName.trim() ?? '';

  Future<bool> keepStandby() async {
    if (!canAnswerBackupOffer) return false;
    try {
      await _case.keepHelpOfferStandby(
        beaconId: state.beaconId,
        offerUserId: state.offerUserId,
      );
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }

  Future<bool> release({required String reason}) async {
    if (!canEndParticipation) return false;
    final offer = state.offer;
    if (offer == null ||
        offer.stakeState != CommitmentStakeState.acknowledged) {
      return false;
    }
    try {
      await _case.releaseCommitment(
        beaconId: state.beaconId,
        offerUserId: state.offerUserId,
        reason: reason,
      );
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }

  bool get canEditRole {
    final offer = state.offer;
    if (offer == null || offer.isWithdrawn) return false;
    if (offer.user.id == state.beacon.author.id) return false;
    return offer.user.id == state.myProfile.id || state.isAuthorOrSteward;
  }

  Future<bool> setRoleLabel(String roleLabel) async {
    if (!canEditRole) return false;
    try {
      await _case.setRoleLabel(
        beaconId: state.beaconId,
        offerUserId: state.offerUserId,
        roleLabel: roleLabel,
      );
      final offer = state.offer;
      if (offer != null && !isClosed) {
        emit(
          state.copyWith(
            offer: offer.copyWith(roleLabel: roleLabel),
          ),
        );
      }
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }
}
