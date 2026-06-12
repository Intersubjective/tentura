import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/contacts/contact_name_store.dart';
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
    this._store, {
    required super.env,
    required super.logger,
  }) {
    _accountSub = _authCase.currentAccountChanges().listen(_onAccountChanged);
  }

  final ContactsRepository _repository;

  final AuthCase _authCase;

  final ContactNameStore _store;

  late final StreamSubscription<String> _accountSub;

  String _accountId = '';

  /// Emits whenever any contact name changes (rename, reset, sync, switch).
  Stream<void> get changes => _store.changes;

  String? nameOf(String userId) => _store.nameOf(userId);

  @disposeMethod
  Future<void> dispose() => _accountSub.cancel();

  Future<void> _onAccountChanged(String accountId) async {
    _accountId = accountId;
    if (accountId.isEmpty) {
      _store.clear();
      return;
    }
    _store.replaceAll(await _repository.getCached(accountId: accountId));
    await refresh();
  }

  /// Re-fetches the full contact map from the server. Keeps the cached map
  /// on network failure — contact names degrade gracefully offline.
  Future<void> refresh() async {
    final accountId = _accountId;
    if (accountId.isEmpty) return;
    try {
      final names = await _repository.fetchMine();
      if (accountId != _accountId) return; // account switched mid-fetch
      await _repository.replaceCache(accountId: accountId, names: names);
      _store.replaceAll(names);
    } catch (e) {
      logger.warning('Contacts sync failed, using cached names', e);
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
