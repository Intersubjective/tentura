import 'dart:async' show StreamSubscription, unawaited;

import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart'
    show HomeScreen;
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
    _loadAccount(_authCubit.state.currentAccountId);
  }

  final SettingsRepositoryPort _settingsRepository;
  final AuthCubit _authCubit;

  late final StreamSubscription<AuthState> _authSub;
  int _accountGeneration = 0;
  String _accountId = '';
  bool _accountInitialized = false;

  void _onAuthState(AuthState auth) {
    _loadAccount(auth.currentAccountId);
  }

  void _loadAccount(String accountId) {
    if (_accountInitialized && accountId == _accountId) return;
    _accountInitialized = true;
    _accountId = accountId;
    final generation = ++_accountGeneration;
    emit(NewStuffState(activeHomeTab: state.activeHomeTab));
    if (accountId.isEmpty) return;
    unawaited(_hydrate(accountId, generation));
  }

  Future<void> _hydrate(String accountId, int generation) async {
    if (accountId.isEmpty) {
      return;
    }
    try {
      final inbox = await _settingsRepository.getNewStuffInboxLastSeenMs(
        accountId,
      );
      final myWork = await _settingsRepository.getNewStuffMyWorkLastSeenMs(
        accountId,
      );
      if (isClosed ||
          generation != _accountGeneration ||
          accountId != _accountId) {
        return;
      }
      emit(
        state.copyWith(
          inboxLastSeenMs: inbox,
          myWorkLastSeenMs: myWork,
          maxInboxActivityMs: null,
          maxMyWorkActivityMs: null,
          inboxNeedsMeCount: 0,
          inboxLoadComplete: false,
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      if (!isClosed) {
        GetIt.I<Logger>().warning('NewStuff hydrate failed', e);
      }
    }
  }

  /// Called from [HomeScreen] when `NavigationBar` selection changes.
  void setActiveHomeTab(HomeTab tab) {
    if (state.activeHomeTab == tab) return;
    emit(state.copyWith(activeHomeTab: tab));
  }

  /// After a successful Inbox fetch: updates max activity snapshot.
  void reportInboxActivity(int? maxLatestForwardMs) {
    emit(state.copyWith(maxInboxActivityMs: maxLatestForwardMs ?? 0));
  }

  /// Needs me count for My Work empty-state CTAs (from `InboxNeedsMeReporter`).
  void reportInboxNeedsMe({required int count, required bool loadComplete}) {
    emit(
      state.copyWith(
        inboxNeedsMeCount: count,
        inboxLoadComplete: loadComplete,
      ),
    );
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
        GetIt.I<Logger>().warning('NewStuff inbox seen persist failed', e);
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
        GetIt.I<Logger>().warning('NewStuff my work seen persist failed', e);
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

  bool get hasNewInboxDot =>
      _authCubit.state.currentAccountId.isNotEmpty &&
      state.activeHomeTab != HomeTab.inbox &&
      state.maxInboxActivityMs != null &&
      state.maxInboxActivityMs! > 0 &&
      (state.inboxLastSeenMs == null ||
          state.maxInboxActivityMs! > state.inboxLastSeenMs!);

  bool get hasNewMyWorkDot =>
      _authCubit.state.currentAccountId.isNotEmpty &&
      state.myWorkLastSeenMs != null &&
      state.maxMyWorkActivityMs != null &&
      state.maxMyWorkActivityMs! > state.myWorkLastSeenMs! &&
      state.activeHomeTab != HomeTab.work;

  @override
  @disposeMethod
  Future<void> close() async {
    await _authSub.cancel();
    return super.close();
  }
}
