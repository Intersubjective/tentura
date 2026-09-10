import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'updates_feed_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'updates_feed_state.dart';

/// Presentation-only projection of the domain-owned attention feed.
final class UpdatesFeedCubit extends Cubit<UpdatesFeedState> {
  UpdatesFeedCubit({
    required String destinationId,
    AttentionCase? attention,
    Logger? logger,
  }) : _destinationId = destinationId,
       _attention = attention ?? GetIt.I<AttentionCase>(),
       _logger = logger ?? GetIt.I<Logger>(),
       super(const UpdatesFeedState()) {
    _attention.attachFeedSession(_destinationId);
    _accountSub = _attention.feedPages.listen((_) => _projectFromDomain());
    _sessionSub = _attention
        .watchFeedSession(_destinationId)
        .listen((_) => _projectFromDomain());
    _projectFromDomain();
    unawaited(_attention.refresh(destinationId: _destinationId));
  }

  final String _destinationId;
  final AttentionCase _attention;
  final Logger _logger;
  late final StreamSubscription<AttentionFeedSnapshot> _accountSub;
  late final StreamSubscription<AttentionFeedSession> _sessionSub;

  void _projectFromDomain() {
    final session = _attention.feedSession(_destinationId);
    final page = session.pages[session.activeView];
    emit(
      state.copyWith(
        view: session.activeView,
        searchText: session.searchText,
        summary: _attention.snapshot.summary,
        items: page?.items ?? const [],
        hasNextPage: page?.nextCursor?.isNotEmpty ?? false,
        refreshError: session.headRefreshError,
        status: const StateIsSuccess(),
      ),
    );
  }

  Future<void> setView(AttentionView view) async {
    if (state.view == view) return;
    emit(
      state.copyWith(
        view: view,
        status: const StateIsLoading(),
        refreshError: null,
        actionError: null,
      ),
    );
    _attention.setActiveView(_destinationId, view);
  }

  void setSearch(String value) => _attention.setSearch(_destinationId, value);

  Future<void> refresh() async {
    emit(state.copyWith(refreshError: null));
    try {
      await _attention.refresh(destinationId: _destinationId);
      _projectFromDomain();
    } catch (error, stackTrace) {
      _logger.warning('Updates refresh failed', error, stackTrace);
      emit(state.copyWith(refreshError: error, status: const StateIsSuccess()));
    }
  }

  Future<void> loadNextPage() async {
    if (!state.hasNextPage) return;
    try {
      await _attention.fetchNextPage(destinationId: _destinationId);
    } catch (error, stackTrace) {
      _logger.warning('Updates pagination failed', error, stackTrace);
      emit(state.copyWith(refreshError: error, status: const StateIsSuccess()));
    }
  }

  Future<void> markSeen(String id) async {
    try {
      await _attention.markSeen([id]);
      emit(state.copyWith(actionError: null));
    } catch (error, stackTrace) {
      _logger.warning('Updates mark-seen failed', error, stackTrace);
      emit(state.copyWith(actionError: error, status: const StateIsSuccess()));
    }
  }

  Future<void> markUnseen(String id) async {
    try {
      await _attention.markUnseen([id]);
      emit(state.copyWith(actionError: null));
    } catch (error, stackTrace) {
      _logger.warning('Updates mark-unseen failed', error, stackTrace);
      emit(state.copyWith(actionError: error, status: const StateIsSuccess()));
    }
  }

  Future<void> markAllSeen() async {
    try {
      await _attention.markAllSeen();
      emit(state.copyWith(actionError: null));
    } catch (error, stackTrace) {
      _logger.warning('Updates mark-all-seen failed', error, stackTrace);
      emit(state.copyWith(actionError: error, status: const StateIsSuccess()));
    }
  }

  Future<void> settle(String id) async {
    try {
      await _attention.settle(id);
      emit(state.copyWith(actionError: null));
    } catch (error, stackTrace) {
      _logger.warning('Updates settle failed', error, stackTrace);
      emit(state.copyWith(actionError: error, status: const StateIsSuccess()));
    }
  }

  @override
  Future<void> close() async {
    _attention.detachFeedSession(_destinationId);
    await _accountSub.cancel();
    await _sessionSub.cancel();
    return super.close();
  }
}
