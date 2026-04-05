import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/commitment_event.dart';

import '../../data/repository/inbox_repository.dart';
import '../../domain/enum.dart';
import 'inbox_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'inbox_state.dart';

class InboxCubit extends Cubit<InboxState> {
  InboxCubit({
    String initialContext = '',
    InboxRepository? repository,
    ForwardRepository? forwardRepository,
  }) : _repository = repository ?? GetIt.I<InboxRepository>(),
       _forwardRepository = forwardRepository ?? GetIt.I<ForwardRepository>(),
       super(const InboxState()) {
    _commitmentChanges = _forwardRepository.commitmentChanges.listen(
      _onCommitmentChanged,
      cancelOnError: false,
    );
    unawaited(fetch(initialContext));
  }

  final InboxRepository _repository;
  final ForwardRepository _forwardRepository;

  late final StreamSubscription<CommitmentEvent> _commitmentChanges;

  void _onCommitmentChanged(CommitmentEvent event) => switch (event) {
        CommitmentCreated(:final beaconId) => _removeInboxItem(beaconId),
        CommitmentWithdrawn() => unawaited(fetch()),
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

  @override
  Future<void> close() async {
    await _commitmentChanges.cancel();
    return super.close();
  }

  Future<void> fetch([String? contextName]) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final items = await _repository.fetch(
        context: contextName ?? state.context,
      );
      emit(
        state.copyWith(
          context: contextName ?? state.context,
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
