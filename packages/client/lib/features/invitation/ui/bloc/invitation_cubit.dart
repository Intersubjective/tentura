// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods
import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
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
    RealtimeSyncCase? realtime,
  }) : _invitationRepository =
           invitationRepository ?? GetIt.I<InvitationRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const InvitationState()) {
    _repoChanges = _invitationRepository.changes.listen((_) {
      unawaited(fetch());
    });
    // Unit tests that do not wire realtime leave it unregistered.
    final sync =
        realtime ??
        (GetIt.I.isRegistered<RealtimeSyncCase>()
            ? GetIt.I<RealtimeSyncCase>()
            : null);
    if (sync != null) {
      // Someone accepting an invitation is a server-side change: the server
      // pushes `relationship` to the inviter (B074). Catch-ups cover a push
      // missed while offline.
      _serverChanges = MergeStream<void>([
        sync
            .changesFor(const {
              RealtimeEntityKind.relationship,
              RealtimeEntityKind.contact,
            })
            .map((_) {}),
        sync.catchUps.map((_) {}),
      ]).listen((_) => _scheduleSilentFetch(), cancelOnError: false);
    }
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
  StreamSubscription<void>? _serverChanges;
  Timer? _refreshTimer;

  static const _refreshDebounce = Duration(milliseconds: 100);

  void _scheduleSilentFetch() {
    if (isClosed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      if (isClosed) return;
      // A load in progress may predate the change; try again after it.
      if (state.isLoading) {
        _scheduleSilentFetch();
        return;
      }
      unawaited(fetch(showError: false));
    });
  }

  /// Reloads both segments' first page, plus the true pending count. Used
  /// for pull-to-refresh, initial load, and whenever the repository reports
  /// a local change (create/update/delete).
  ///
  /// [showError] is false for background refetches: a failure there keeps
  /// the visible lists without a snackbar.
  Future<void> fetch({bool showError = true}) async {
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
      if (showError) {
        _emitSnackError(e);
      } else if (!isClosed) {
        emit(state.copyWith(status: StateStatus.isSuccess));
      }
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
    _refreshTimer?.cancel();
    await _repoChanges?.cancel();
    await _serverChanges?.cancel();
    return super.close();
  }
}
