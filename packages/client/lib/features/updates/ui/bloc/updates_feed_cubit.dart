import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'updates_feed_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'updates_feed_state.dart';

/// Presentation-only projection of the domain-owned attention feed.
final class UpdatesFeedCubit extends Cubit<UpdatesFeedState> {
  UpdatesFeedCubit({
    required String destinationId,
    AttentionView? pinnedView,
    AttentionCase? attention,
    InviteAcceptedSetupPort? setup,
    RealtimeSyncCase? realtime,
    Logger? logger,
  }) : _destinationId = destinationId,
       _attention = attention ?? GetIt.I<AttentionCase>(),
       _setup = setup ?? GetIt.I<InviteAcceptedSetupPort>(),
       _realtime = realtime ?? GetIt.I<RealtimeSyncCase>(),
       _logger = logger ?? GetIt.I<Logger>(),
       super(const UpdatesFeedState()) {
    _attention.attachFeedSession(_destinationId);
    if (pinnedView != null) {
      _attention.setActiveView(_destinationId, pinnedView);
    }
    _accountSub = _attention.feedPages.listen((_) => _projectFromDomain());
    _sessionSub = _attention
        .watchFeedSession(_destinationId)
        .listen((_) => _projectFromDomain());
    _promptInvalidationSub = _realtime
        .changesFor(const {RealtimeEntityKind.inviteSeedPrompt})
        .listen(_onPromptInvalidation);
    _projectFromDomain();
    unawaited(_attention.refresh(destinationId: _destinationId));
  }

  final String _destinationId;
  final AttentionCase _attention;
  final InviteAcceptedSetupPort _setup;
  final RealtimeSyncCase _realtime;
  final Logger _logger;
  late final StreamSubscription<AttentionFeedSnapshot> _accountSub;
  late final StreamSubscription<AttentionFeedSession> _sessionSub;
  late final StreamSubscription<RealtimeEntityChange> _promptInvalidationSub;
  int _promptFetchEpoch = 0;

  void _projectFromDomain() {
    final session = _attention.feedSession(_destinationId);
    final page = session.pages[session.activeView];
    final items = page?.items ?? const <AttentionReceipt>[];
    emit(
      state.copyWith(
        view: session.activeView,
        searchText: session.searchText,
        summary: _attention.snapshot.summary,
        items: items,
        hasNextPage: page?.nextCursor?.isNotEmpty ?? false,
        refreshError: session.headRefreshError,
        status: const StateIsSuccess(),
      ),
    );
    _schedulePromptSync(items);
  }

  void _onPromptInvalidation(RealtimeEntityChange change) {
    final subjectId = change.aggregateId;
    if (subjectId.isEmpty) return;
    unawaited(_refreshPromptProjections({subjectId}, force: true));
  }

  void _schedulePromptSync(List<AttentionReceipt> items) {
    final subjectIds = <String>{};
    for (final receipt in items) {
      if (!receiptNeedsInvitePromptProjection(receipt)) continue;
      final subjectId = inviteAcceptedPromptSubjectId(receipt);
      if (subjectId == null) continue;
      final current = state.promptProjections[subjectId];
      if (current != null && !current.isUnknown) continue;
      subjectIds.add(subjectId);
    }
    if (subjectIds.isEmpty) return;
    unawaited(_refreshPromptProjections(subjectIds));
  }

  Future<void> retryPromptFetch(String subjectId) =>
      _refreshPromptProjections({subjectId}, force: true);

  void applyKnownPrompt(String subjectId, InviteSeedPromptState prompt) {
    final next = Map<String, PromptProjection>.from(state.promptProjections);
    next[subjectId] = PromptProjection.known(prompt);
    emit(state.copyWith(promptProjections: next));
  }

  Future<void> _refreshPromptProjections(
    Set<String> subjectIds, {
    bool force = false,
  }) async {
    if (subjectIds.isEmpty) return;
    final epoch = ++_promptFetchEpoch;
    try {
      final states = await _setup.fetchPrompts(subjectIds);
      if (!isClosed && epoch == _promptFetchEpoch) {
        final next = Map<String, PromptProjection>.from(state.promptProjections);
        for (final id in subjectIds) {
          final prompt = states[id];
          if (prompt != null) {
            next[id] = PromptProjection.known(prompt);
          } else if (force && next[id] is PromptProjectionKnown) {
            next.remove(id);
          }
        }
        emit(state.copyWith(promptProjections: next));
      }
    } catch (error, stackTrace) {
      _logger.warning('Invite prompt projection fetch failed', error, stackTrace);
      if (!isClosed && epoch == _promptFetchEpoch) {
        final next = Map<String, PromptProjection>.from(state.promptProjections);
        for (final id in subjectIds) {
          final current = next[id];
          if (current == null || current.isUnknown || force) {
            next[id] = const PromptProjection.failed();
          }
        }
        emit(state.copyWith(promptProjections: next));
      }
    }
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
    await _promptInvalidationSub.cancel();
    return super.close();
  }
}
