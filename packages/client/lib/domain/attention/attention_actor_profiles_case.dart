import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import 'port/attention_account_port.dart';

/// Shared missing-id cache for Activity / History actor avatars.
///
/// Contact-name overlay is applied at **build** time (see
/// `profileWithContactOverlay`); this case only loads image + displayName.
/// A later contact rename shows on the next cubit rebuild — listening to
/// [ContactNameStore.changes] is optional and not required for correctness.
@lazySingleton
final class AttentionActorProfilesCase {
  AttentionActorProfilesCase(
    this._profiles,
    this._account,
  ) {
    _accountSub = _account.currentAccountChanges.listen(_onAccountChanged);
  }

  final ProfileRepositoryPort _profiles;
  final AttentionAccountPort _account;

  final Map<String, Profile> _cache = {};
  final Set<String> _negative = {};

  /// Ids currently being fetched → shared future (in-flight dedupe).
  final Map<String, Future<void>> _inFlight = {};

  late final StreamSubscription<String> _accountSub;

  /// Returns cached profiles for [ids], fetching only missing ones.
  ///
  /// Misses (deleted / blocked / unreadable) are negative-cached so repeated
  /// hydrate calls do not hammer Hasura. Concurrent [resolve] calls for the
  /// same ids share one in-flight batch.
  Future<Map<String, Profile>> resolve(Set<String> ids) async {
    final wanted = {
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    };
    if (wanted.isEmpty) return const {};

    var missing = <String>{
      for (final id in wanted)
        if (!_cache.containsKey(id) && !_negative.contains(id)) id,
    };

    while (missing.isNotEmpty) {
      final waiting = <Future<void>>[
        for (final id in missing)
          if (_inFlight.containsKey(id)) _inFlight[id]!,
      ];
      if (waiting.isNotEmpty) {
        await Future.wait(waiting);
        missing = {
          for (final id in missing)
            if (!_cache.containsKey(id) && !_negative.contains(id)) id,
        };
        continue;
      }

      final batchIds = Set<String>.of(missing);
      final batch = _fetchBatch(batchIds);
      for (final id in batchIds) {
        _inFlight[id] = batch;
      }
      try {
        await batch;
      } finally {
        for (final id in batchIds) {
          _inFlight.remove(id);
        }
      }
      missing = {
        for (final id in missing)
          if (!_cache.containsKey(id) && !_negative.contains(id)) id,
      };
    }

    return {
      for (final id in wanted)
        if (_cache.containsKey(id)) id: _cache[id]!,
    };
  }

  Future<void> _fetchBatch(Set<String> ids) async {
    try {
      final rows = await _profiles.fetchProfilesByIds(ids);
      final found = <String>{};
      for (final profile in rows) {
        if (profile.id.isEmpty) continue;
        _cache[profile.id] = profile;
        _negative.remove(profile.id);
        found.add(profile.id);
      }
      for (final id in ids) {
        if (!found.contains(id)) {
          _negative.add(id);
        }
      }
    } on Object {
      _negative.addAll(ids);
    }
  }

  void clear() {
    _cache.clear();
    _negative.clear();
    _inFlight.clear();
  }

  void _onAccountChanged(String _) {
    clear();
  }

  @disposeMethod
  Future<void> dispose() async {
    await _accountSub.cancel();
    clear();
  }
}
