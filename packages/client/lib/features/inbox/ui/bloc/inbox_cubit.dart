import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';

import '../../data/repository/inbox_repository.dart';
import '../../domain/enum.dart';
import '../message/inbox_messages.dart';
import 'inbox_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'inbox_state.dart';

class InboxCubit extends Cubit<InboxState> {
  InboxCubit({
    required String userId,
    InboxRepository? repository,
    ForwardRepository? forwardRepository,
  }) : _userId = userId,
       _repository = repository ?? GetIt.I<InboxRepository>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       super(InboxState(currentUserId: userId)) {
    _commitmentChanges = _forwardRepository.commitmentChanges.listen(
      _onCommitmentChanged,
      cancelOnError: false,
    );
    _forwardCompleted = _forwardRepository.forwardCompleted.listen(
      _fetchAndNotifyIfMoved,
      cancelOnError: false,
    );
    _inboxLocalMutations = _repository.localMutations.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  final String _userId;
  final InboxRepository _repository;
  final ForwardRepository _forwardRepository;

  late final StreamSubscription<CommitmentEvent> _commitmentChanges;
  late final StreamSubscription<String> _forwardCompleted;
  late final StreamSubscription<void> _inboxLocalMutations;

  void _onCommitmentChanged(CommitmentEvent event) => switch (event) {
        CommitmentCreated(:final beaconId) => _removeInboxItem(beaconId),
        CommitmentWithdrawn() ||
        CommitmentInvalidated() =>
          unawaited(fetch(showLoading: false)),
      };

  void _removeInboxItem(String beaconId) {
    if (isClosed) return;
    emit(
      state.copyWith(
        items: state.items.where((e) => e.beaconId != beaconId).toList(),
        status: const StateIsSuccess(),
      ),
    );
  }

  Future<void> _fetchAndNotifyIfMoved(String beaconId) async {
    if (isClosed) return;
    final previousIdx = state.items.indexWhere((e) => e.beaconId == beaconId);
    final previousStatus =
        previousIdx >= 0 ? state.items[previousIdx].status : null;

    await fetch(showLoading: false);

    if (isClosed) return;
    if (state.hasError) return;

    final newIdx = state.items.indexWhere((e) => e.beaconId == beaconId);
    if (newIdx < 0) return;
    final newStatus = state.items[newIdx].status;

    if (previousStatus == newStatus) return;
    if (newStatus != InboxItemStatus.watching &&
        newStatus != InboxItemStatus.rejected) {
      return;
    }

    final item = state.items[newIdx];
    final ownBeaconForward = newStatus == InboxItemStatus.watching &&
        item.beacon?.author.id == _userId;

    emit(
      state.copyWith(
        status: StateIsMessaging(
          InboxBeaconMovedMessage(
            beaconId: beaconId,
            toStatus: newStatus,
            ownBeaconForward: ownBeaconForward,
          ),
        ),
      ),
    );
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  @override
  Future<void> close() async {
    await _commitmentChanges.cancel();
    await _forwardCompleted.cancel();
    await _inboxLocalMutations.cancel();
    return super.close();
  }

  Future<void> fetch({bool showLoading = true}) async {
    if (showLoading) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      final items = await _repository.fetch(userId: _userId);
      emit(
        state.copyWith(
          items: items,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  void setSort(InboxSort sort) {
    emit(state.copyWith(sort: sort));
  }

  Future<void> setWatching(String beaconId) async {
    await _updateStatus(beaconId, InboxItemStatus.watching);
  }

  Future<void> stopWatching(String beaconId) async {
    await _updateStatus(beaconId, InboxItemStatus.needsMe);
  }

  Future<void> reject(String beaconId, {String message = ''}) async {
    await _updateStatus(
      beaconId,
      InboxItemStatus.rejected,
      rejectionMessage: message,
    );
  }

  Future<void> unreject(String beaconId) async {
    await _updateStatus(
      beaconId,
      InboxItemStatus.needsMe,
    );
  }

  Future<void> dismissTombstone(String beaconId) async {
    final idx = state.items.indexWhere((e) => e.beaconId == beaconId);
    if (idx < 0) return;
    final item = state.items[idx];
    if (!item.isTombstoneVisible) return;
    final dismissedAt = DateTime.now().toUtc();
    try {
      await _repository.dismissTombstone(
        beaconId: beaconId,
        dismissedAt: dismissedAt,
      );
      emit(
        state.copyWith(
          items: [
            ...state.items.sublist(0, idx),
            item.copyWith(tombstoneDismissedAt: dismissedAt),
            ...state.items.sublist(idx + 1),
          ],
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _updateStatus(
    String beaconId,
    InboxItemStatus status, {
    String rejectionMessage = '',
  }) async {
    final idx = state.items.indexWhere((e) => e.beaconId == beaconId);
    if (idx < 0) return;
    final item = state.items[idx];
    try {
      await _repository.setStatus(
        beaconId: beaconId,
        status: status,
        rejectionMessage: rejectionMessage,
      );
      emit(
        state.copyWith(
          items: [
            ...state.items.sublist(0, idx),
            item.copyWith(
              status: status,
              rejectionMessage: rejectionMessage,
            ),
            ...state.items.sublist(idx + 1),
          ],
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
