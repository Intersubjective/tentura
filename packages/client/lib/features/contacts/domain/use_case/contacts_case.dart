import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../data/repository/contacts_repository.dart';

/// Subjective profiles orchestrator: keeps [ContactNameStore] in sync with
/// the current account — Drift cache first (instant, offline), then the
/// server's `myContacts` map — and applies renames/resets.
@singleton
final class ContactsCase extends UseCaseBase {
  ContactsCase(
    this._repository,
    this._authCase,
    this._store,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  }) {
    _accountSub = _authCase.currentAccountChanges().listen(_onAccountChanged);
    _contactSub = _realtimeSyncCase
        .changesFor(const {RealtimeEntityKind.contact})
        .listen((_) => _scheduleRefresh(), cancelOnError: false);
    _catchUpSub = _realtimeSyncCase.catchUps.listen(
      (_) => _scheduleRefresh(),
      cancelOnError: false,
    );
  }

  final ContactsRepository _repository;

  final AuthCase _authCase;

  final ContactNameStore _store;

  final RealtimeSyncCase _realtimeSyncCase;

  late final StreamSubscription<String> _accountSub;
  late final StreamSubscription<RealtimeEntityChange> _contactSub;
  late final StreamSubscription<RealtimeCatchUp> _catchUpSub;

  static const _refreshDebounce = Duration(milliseconds: 100);
  Timer? _refreshTimer;
  Future<void>? _activeRefresh;
  bool _refreshPending = false;
  bool _disposed = false;

  String _accountId = '';

  /// Emits whenever any contact name changes (rename, reset, sync, switch).
  Stream<void> get changes => _store.changes;

  String? nameOf(String userId) => _store.nameOf(userId);

  @disposeMethod
  Future<void> dispose() async {
    _disposed = true;
    _refreshTimer?.cancel();
    await _accountSub.cancel();
    await _contactSub.cancel();
    await _catchUpSub.cancel();
  }

  Future<void> _onAccountChanged(String accountId) async {
    _accountId = accountId;
    _activeRefresh = null;
    _refreshPending = false;
    if (accountId.isEmpty) {
      _store.clear();
      return;
    }
    final cached = await _repository.getCached(accountId: accountId);
    if (_disposed || accountId != _accountId) return;
    _store.replaceAll(cached);
    await refresh();
  }

  void _scheduleRefresh() {
    if (_disposed || _accountId.isEmpty) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_refreshDebounce, () {
      _refreshTimer = null;
      unawaited(refresh());
    });
  }

  /// Re-fetches the full contact map from the server. Keeps the cached map
  /// on network failure — contact names degrade gracefully offline.
  Future<void> refresh() {
    final active = _activeRefresh;
    if (active != null) {
      _refreshPending = true;
      return active;
    }
    late final Future<void> future;
    final accountId = _accountId;
    future = _runRefreshLoop(accountId).whenComplete(() {
      if (identical(_activeRefresh, future)) {
        _activeRefresh = null;
      }
    });
    _activeRefresh = future;
    return future;
  }

  Future<void> _runRefreshLoop(String accountId) async {
    do {
      _refreshPending = false;
      await _refreshOnce(accountId);
    } while (_refreshPending && !_disposed && accountId == _accountId);
  }

  Future<void> _refreshOnce(String accountId) async {
    if (_disposed || accountId.isEmpty) return;
    try {
      final names = await _repository.fetchMine();
      if (_disposed || accountId != _accountId) return;
      await _repository.replaceCache(accountId: accountId, names: names);
      if (_disposed || accountId != _accountId) return;
      _store.replaceAll(names);
    } catch (e) {
      if (!_disposed && accountId == _accountId) {
        logger.warning('Contacts sync failed, using cached names', e);
      }
    }
  }

  /// Sets the current account's private name for [subjectId] (online-only).
  Future<void> rename({
    required String subjectId,
    required String contactName,
  }) async {
    final name = contactName.trim();
    await _repository.setContact(subjectId: subjectId, contactName: name);
    await _repository.putCached(
      accountId: _accountId,
      subjectId: subjectId,
      contactName: name,
    );
    _store.set(subjectId, name);
  }

  /// Removes the contact entry — the subject's self-chosen name shows again.
  Future<void> reset({required String subjectId}) async {
    await _repository.deleteContact(subjectId: subjectId);
    await _repository.removeCached(
      accountId: _accountId,
      subjectId: subjectId,
    );
    _store.remove(subjectId);
  }
}
