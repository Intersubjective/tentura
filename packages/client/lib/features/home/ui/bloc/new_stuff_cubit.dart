import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart' show HomeScreen;
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'new_stuff_highlight.dart';
import 'new_stuff_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'new_stuff_highlight.dart';
export 'new_stuff_state.dart';

/// Tracks "new since last visit" for Inbox and My Work tabs (local Drift cursors).
@singleton
class NewStuffCubit extends Cubit<NewStuffState> {
  NewStuffCubit(
    this._settingsRepository,
    this._authCubit,
  ) : super(const NewStuffState()) {
    _authSub = _authCubit.stream.listen(_onAuthState);
    unawaited(_hydrate(_authCubit.state.currentAccountId));
  }

  final SettingsRepositoryPort _settingsRepository;
  final AuthCubit _authCubit;

  late final StreamSubscription<AuthState> _authSub;

  void _onAuthState(AuthState auth) {
    unawaited(_hydrate(auth.currentAccountId));
  }

  Future<void> _hydrate(String accountId) async {
    if (accountId.isEmpty) {
      emit(const NewStuffState());
      return;
    }
    try {
      final inbox = await _settingsRepository.getNewStuffInboxLastSeenMs(
        accountId,
      );
      final myWork = await _settingsRepository.getNewStuffMyWorkLastSeenMs(
        accountId,
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          inboxLastSeenMs: inbox,
          myWorkLastSeenMs: myWork,
          maxInboxActivityMs: null,
          maxMyWorkActivityMs: null,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  /// Called from [HomeScreen] when `NavigationBar` selection changes.
  void setActiveHomeTabIndex(int index) {
    if (state.activeHomeTabIndex == index) return;
    emit(state.copyWith(activeHomeTabIndex: index));
  }

  /// After a successful Inbox fetch: updates max activity snapshot.
  void reportInboxActivity(int? maxLatestForwardMs) {
    emit(state.copyWith(maxInboxActivityMs: maxLatestForwardMs ?? 0));
  }

  /// After a successful My Work fetch: updates max activity snapshot.
  void reportMyWorkActivity(int? maxBeaconUpdatedMs) {
    emit(state.copyWith(maxMyWorkActivityMs: maxBeaconUpdatedMs ?? 0));
  }

  /// User left the Inbox tab: advance last-seen to current max activity.
  Future<void> markInboxTabSeen() async {
    final accountId = _authCubit.state.currentAccountId;
    if (accountId.isEmpty) return;
    final maxMs = state.maxInboxActivityMs;
    if (maxMs == null) return;
    await _persistInboxSeen(accountId, maxMs);
  }

  /// User left the My Work tab: advance last-seen to current max activity.
  Future<void> markMyWorkTabSeen() async {
    final accountId = _authCubit.state.currentAccountId;
    if (accountId.isEmpty) return;
    final maxMs = state.maxMyWorkActivityMs;
    if (maxMs == null) return;
    await _persistMyWorkSeen(accountId, maxMs);
  }

  Future<void> _persistInboxSeen(String accountId, int ms) async {
    try {
      await _settingsRepository.setNewStuffInboxLastSeenMs(accountId, ms);
      if (isClosed) return;
      emit(state.copyWith(inboxLastSeenMs: ms));
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  Future<void> _persistMyWorkSeen(String accountId, int ms) async {
    try {
      await _settingsRepository.setNewStuffMyWorkLastSeenMs(accountId, ms);
      if (isClosed) return;
      emit(state.copyWith(myWorkLastSeenMs: ms));
    } catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: StateHasError(e)));
      }
    }
  }

  /// Inbox row: new forward activity vs beacon-only update since last visit.
  InboxRowHighlightKind inboxRowHighlight({
    required DateTime latestForwardAt,
    required int forwardCount,
    required int beaconActivityEpochMs,
  }) {
    final seen = state.inboxLastSeenMs;
    if (seen == null) return InboxRowHighlightKind.none;
    final forwardMs = latestForwardAt.millisecondsSinceEpoch;
    if (forwardCount > 0 && forwardMs > seen) {
      return InboxRowHighlightKind.newForwardActivity;
    }
    if (beaconActivityEpochMs > seen) {
      return InboxRowHighlightKind.updatedBeaconOnly;
    }
    return InboxRowHighlightKind.none;
  }

  /// My Work card: brand-new beacon vs backend activity since last visit.
  MyWorkCardHighlightKind myWorkCardHighlight({
    required DateTime createdAt,
    required int activityEpochMs,
  }) {
    final seen = state.myWorkLastSeenMs;
    if (seen == null) return MyWorkCardHighlightKind.none;
    final cMs = createdAt.millisecondsSinceEpoch;
    if (cMs > seen) return MyWorkCardHighlightKind.newBeacon;
    if (activityEpochMs > seen) return MyWorkCardHighlightKind.updatedBeaconOnly;
    return MyWorkCardHighlightKind.none;
  }

  bool get hasNewInboxDot =>
      _authCubit.state.currentAccountId.isNotEmpty &&
      state.inboxLastSeenMs != null &&
      state.maxInboxActivityMs != null &&
      state.maxInboxActivityMs! > state.inboxLastSeenMs! &&
      state.activeHomeTabIndex != 0;

  bool get hasNewMyWorkDot =>
      _authCubit.state.currentAccountId.isNotEmpty &&
      state.myWorkLastSeenMs != null &&
      state.maxMyWorkActivityMs != null &&
      state.maxMyWorkActivityMs! > state.myWorkLastSeenMs! &&
      state.activeHomeTabIndex != 1;

  @override
  @disposeMethod
  Future<void> close() async {
    await _authSub.cancel();
    return super.close();
  }
}
