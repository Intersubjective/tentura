import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/bloc/timeline_help_offer_mapping.dart';
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

  bool get canManageOffer {
    final offer = state.offer;
    if (offer == null || offer.isWithdrawn) return false;
    if (offer.offerKind == 1) return false;
    final beacon = state.beacon;
    if (!beacon.status.isOpenFamily) return false;
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
      return true;
    } catch (e) {
      _effects.emit(ShowError(e));
      return false;
    }
  }

  Future<bool> decline({required String reason}) async {
    if (!canManageOffer) return false;
    try {
      await _case.declineHelpOffer(
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

  Future<bool> release({required String reason}) async {
    if (!canManageOffer) return false;
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
