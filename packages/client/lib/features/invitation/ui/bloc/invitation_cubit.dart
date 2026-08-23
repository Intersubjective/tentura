// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods
import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../data/repository/invitation_repository.dart';
import 'invitation_state.dart';

export 'invitation_state.dart';

class InvitationCubit extends Cubit<InvitationState> {
  InvitationCubit({
    InvitationRepository? invitationRepository,
    UiEffectPort? effects,
  }) : _invitationRepository =
           invitationRepository ?? GetIt.I<InvitationRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const InvitationState()) {
    _repoChanges = _invitationRepository.changes.listen((_) {
      unawaited(fetch());
    });
  }

  final InvitationRepository _invitationRepository;

  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: StateStatus.isSuccess));
    }
  }

  StreamSubscription<void>? _repoChanges;

  /// Reloads both segments' first page, plus the true pending count. Used
  /// for pull-to-refresh, initial load, and whenever the repository reports
  /// a local change (create/update/delete).
  Future<void> fetch() async {
    if (state.isLoading) {
      return;
    }

    // Keep the current lists while loading — a failed refetch must not
    // wipe what the user already sees (counts, list rows).
    emit(state.copyWith(status: StateStatus.isLoading));

    try {
      final result = await _invitationRepository.fetchMine();
      final pending = [...result.pending]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final accepted = [...result.accepted]
        ..sort((a, b) => b.acceptedAt!.compareTo(a.acceptedAt!));
      emit(
        state.copyWith(
          pendingInvitations: pending,
          acceptedInvitations: accepted,
          pendingCount: result.pendingCount,
          pendingHasReachedMax: result.pending.length < kFetchListOffset,
          acceptedHasReachedMax: result.accepted.length < kFetchListOffset,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  /// Paginates the Pending segment forward without touching Accepted.
  Future<void> fetchMorePending() async {
    if (state.isLoading || state.pendingHasReachedMax) {
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));

    try {
      final result = await _invitationRepository.fetchMine(
        pendingOffset: state.pendingInvitations.length,
        acceptedLimit: 0,
      );
      final pending = [...state.pendingInvitations, ...result.pending]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(
        state.copyWith(
          pendingInvitations: pending,
          pendingCount: result.pendingCount,
          pendingHasReachedMax: result.pending.length < kFetchListOffset,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  /// Paginates the Accepted segment forward without touching Pending.
  Future<void> fetchMoreAccepted() async {
    if (state.isLoading || state.acceptedHasReachedMax) {
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));

    try {
      final result = await _invitationRepository.fetchMine(
        pendingLimit: 0,
        acceptedOffset: state.acceptedInvitations.length,
      );
      final accepted = [...state.acceptedInvitations, ...result.accepted]
        ..sort((a, b) => b.acceptedAt!.compareTo(a.acceptedAt!));
      emit(
        state.copyWith(
          acceptedInvitations: accepted,
          acceptedHasReachedMax: result.accepted.length < kFetchListOffset,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _emitSnackError(e);
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
        ...state.pendingInvitations,
        invitation,
      ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      emit(
        state.copyWith(
          pendingInvitations: next,
          pendingCount: state.pendingCount + 1,
          status: StateStatus.isSuccess,
        ),
      );
      return invitation;
    } catch (e) {
      _emitSnackError(e);
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
        for (final e in state.pendingInvitations) e.id == id ? updated : e,
      ];
      emit(
        state.copyWith(pendingInvitations: next, status: StateStatus.isSuccess),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<void> deleteInvitationById(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _invitationRepository.deleteById(id);
      final next = state.pendingInvitations.where((e) => e.id != id).toList();
      emit(
        state.copyWith(
          pendingInvitations: next,
          pendingCount: state.pendingCount > 0 ? state.pendingCount - 1 : 0,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  @override
  Future<void> close() async {
    await _repoChanges?.cancel();
    return super.close();
  }
}
