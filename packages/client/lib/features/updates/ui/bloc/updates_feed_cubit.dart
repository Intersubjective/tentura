import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_actor_ids.dart';
import 'package:tentura/domain/attention/attention_actor_profiles_case.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/attention_dismissible_membership.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'updates_feed_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'updates_feed_state.dart';

/// A clear that did not apply, said as a muted (non-error) line (#601).
enum UpdatesClearNotice {
  /// The server answered `stale`: it was already cleared.
  stale,

  /// The server answered `denied`: it cannot be cleared from here.
  denied,
}

/// Presentation-only projection of the domain-owned attention feed.
final class UpdatesFeedCubit extends Cubit<UpdatesFeedState> {
  UpdatesFeedCubit({
    required String destinationId,
    AttentionView? pinnedView,
    AttentionCase? attention,
    InviteAcceptedSetupPort? setup,
    AttentionActorProfilesCase? actorProfiles,
    RealtimeSyncCase? realtime,
    Logger? logger,
  }) : _destinationId = destinationId,
       _attention = attention ?? GetIt.I<AttentionCase>(),
       _setup = setup ?? GetIt.I<InviteAcceptedSetupPort>(),
       _actorProfiles = actorProfiles ?? GetIt.I<AttentionActorProfilesCase>(),
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
  final AttentionActorProfilesCase _actorProfiles;
  final RealtimeSyncCase _realtime;
  final Logger _logger;
  late final StreamSubscription<AttentionFeedSnapshot> _accountSub;
  late final StreamSubscription<AttentionFeedSession> _sessionSub;
  late final StreamSubscription<RealtimeEntityChange> _promptInvalidationSub;
  final _clearNotices = StreamController<UpdatesClearNotice>.broadcast();
  int _promptFetchEpoch = 0;
  int _actorsGeneration = 0;

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
    unawaited(_hydrateActors(items));
  }

  Future<void> _hydrateActors(List<AttentionReceipt> items) async {
    final ids = attentionActorIds(items);
    if (ids.isEmpty) {
      if (state.actors.isNotEmpty) {
        emit(state.copyWith(actors: const {}));
      }
      return;
    }
    final generation = ++_actorsGeneration;
    try {
      final resolved = await _actorProfiles.resolve(ids);
      if (isClosed || generation != _actorsGeneration) return;
      final next = <String, Profile>{
        ...state.actors,
        ...resolved,
      };
      // Drop actors no longer referenced by the visible page.
      next.removeWhere((id, _) => !ids.contains(id));
      emit(state.copyWith(actors: next));
    } on Object catch (error, stackTrace) {
      _logger.warning('Actor profile hydrate failed', error, stackTrace);
    }
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
        final next = Map<String, PromptProjection>.from(
          state.promptProjections,
        );
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
      _logger.warning(
        'Invite prompt projection fetch failed',
        error,
        stackTrace,
      );
      if (!isClosed && epoch == _promptFetchEpoch) {
        final next = Map<String, PromptProjection>.from(
          state.promptProjections,
        );
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

  /// The explicit per-item "Mark seen" action (#336): reads the item **and**
  /// clears it by hand, so it leaves Unread and the Unread count drops.
  /// Opening a row only reads it — see [markRead].
  ///
  /// Returns false when the action failed ([UpdatesFeedState.actionError]).
  Future<bool> markSeen(String id) async {
    try {
      final receipt = _receiptById(id);
      await _attention.markSeen([id]);
      UpdatesClearNotice? notice;
      if (receipt == null || isActiveOptional(receipt)) {
        notice = _clearNoticeFor(
          await _attention.clearReceipt(receiptId: id),
        );
      }
      if (!isClosed) emit(state.copyWith(actionError: null));
      _sayClearNotice(notice);
      return true;
    } catch (error, stackTrace) {
      _logger.warning('Updates mark-seen failed', error, stackTrace);
      if (!isClosed) {
        emit(
          state.copyWith(actionError: error, status: const StateIsSuccess()),
        );
      }
      return false;
    }
  }

  /// Opening a row: moves the read axis only; the row stays on Unread.
  Future<void> markRead(String id) async {
    try {
      await _attention.markSeen([id]);
      emit(state.copyWith(actionError: null));
    } catch (error, stackTrace) {
      _logger.warning('Updates mark-read failed', error, stackTrace);
      emit(state.copyWith(actionError: error, status: const StateIsSuccess()));
    }
  }

  AttentionReceipt? _receiptById(String id) {
    for (final receipt in state.items) {
      if (receipt.id == id) return receipt;
    }
    return null;
  }

  /// "Mark unread" (#601): returns false when it failed
  /// ([UpdatesFeedState.actionError]) so the caller can say so.
  ///
  /// The Unread view is the clear axis, so on a cleared (Done) optional item
  /// this un-clears it ([AttentionCase.markUnread]); otherwise it only moves
  /// the read dot.
  Future<bool> markUnseen(String id) {
    final receipt = _receiptById(id);
    final cleared =
        receipt != null && receipt.isCleared && !receipt.requiresAction;
    return _runAction(
      'mark-unseen',
      () => cleared ? _attention.markUnread([id]) : _attention.markUnseen([id]),
    );
  }

  /// "Read all" (#601, #258): reads everything **and** clears the active
  /// optional rows, like the per-item [markSeen], in one bounded server sweep
  /// ([AttentionCase.readAll]); obligations are only read (they leave Unread
  /// when settled). A stale or denied member is not news here, so no
  /// [clearNotices] line. Returns false when it failed.
  Future<bool> markAllSeen() => _runAction('mark-all-seen', () async {
    await _attention.readAll();
  });

  /// A clear the server answered `stale` (already gone) or `denied` is not a
  /// failure, but it is not silence either (#601): a muted line says so.
  Stream<UpdatesClearNotice> get clearNotices => _clearNotices.stream;

  static UpdatesClearNotice? _clearNoticeFor(AttentionClearResult result) =>
      switch (result.status) {
        AttentionOperationStatus.stale => UpdatesClearNotice.stale,
        AttentionOperationStatus.denied => UpdatesClearNotice.denied,
        _ => null,
      };

  void _sayClearNotice(UpdatesClearNotice? notice) {
    if (notice != null && !_clearNotices.isClosed) _clearNotices.add(notice);
  }

  /// "Mark done" (#601): returns false when it failed.
  Future<bool> settle(String id) =>
      _runAction('settle', () => _attention.settle(id));

  Future<bool> _runAction(String name, Future<void> Function() action) async {
    try {
      await action();
      if (!isClosed) emit(state.copyWith(actionError: null));
      return true;
    } catch (error, stackTrace) {
      _logger.warning('Updates $name failed', error, stackTrace);
      if (!isClosed) {
        emit(
          state.copyWith(actionError: error, status: const StateIsSuccess()),
        );
      }
      return false;
    }
  }

  @override
  Future<void> close() async {
    _attention.detachFeedSession(_destinationId);
    await _accountSub.cancel();
    await _sessionSub.cancel();
    await _promptInvalidationSub.cancel();
    await _clearNotices.close();
    return super.close();
  }
}
