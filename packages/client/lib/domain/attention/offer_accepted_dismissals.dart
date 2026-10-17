import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

/// Where the dismissed «offer accepted» sub-cards are kept: per account on
/// the server (B077b), so every device of the account agrees.
abstract interface class OfferAcceptedDismissalPort {
  /// The Requests on which [viewerId] dismissed the sub-card.
  Future<Set<String>> load({required String viewerId});

  /// Records one dismissal; returns the Requests known dismissed after it.
  /// Throws [OfferAcceptedDismissalRefusedException] when the server refuses
  /// it; any other error is treated as passing (offline, busy).
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  });
}

/// The server answered and refused a dismissal (for example, the offer was
/// withdrawn meanwhile). Unlike a network failure, sending it again cannot
/// help, so it is dropped rather than kept for the next try.
final class OfferAcceptedDismissalRefusedException implements Exception {
  const OfferAcceptedDismissalRefusedException();
}

/// Keeps nothing between sessions; the fallback where no store is wired
/// (tests, previews).
final class InMemoryOfferAcceptedDismissalPort
    implements OfferAcceptedDismissalPort {
  final _byViewer = <String, Set<String>>{};

  @override
  Future<Set<String>> load({required String viewerId}) async => {
    ...?_byViewer[viewerId],
  };

  @override
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  }) async => {...(_byViewer[viewerId] ??= {})..add(beaconId)};
}

/// B077 — which «your offer was accepted» event sub-cards the viewer has
/// dismissed with ×.
///
/// One dismissal per viewer and Request covers every place the sub-card is
/// shown (the Requests tab card and the Request's People tab), and through
/// [OfferAcceptedDismissalPort] every device of the account (B077b).
@Singleton(env: [Environment.dev, Environment.prod])
class OfferAcceptedDismissals extends ChangeNotifier {
  OfferAcceptedDismissals(this._port);

  /// The store in use: the registered one, else a session-only fallback.
  static OfferAcceptedDismissals get instance =>
      GetIt.I.isRegistered<OfferAcceptedDismissals>()
      ? GetIt.I<OfferAcceptedDismissals>()
      : _fallback ??= OfferAcceptedDismissals(
          InMemoryOfferAcceptedDismissalPort(),
        );

  static OfferAcceptedDismissals? _fallback;

  /// How long after a failed read the next [ensureLoadedFor] may read again.
  static const retryDelay = Duration(seconds: 30);

  /// How long after a successful read the next [ensureLoadedFor] reads again,
  /// so an open device learns of dismissals made on another one.
  static const refreshAfter = Duration(seconds: 30);

  /// Test seam for [retryDelay] and [refreshAfter].
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  static String keyFor({required String viewerId, required String beaconId}) =>
      '$viewerId:$beaconId';

  final OfferAcceptedDismissalPort _port;

  final _keys = <String>{};

  /// Viewers whose dismissals were read (or could not be read).
  final _known = <String>{};

  /// Viewers whose last read failed, with when: [ensureLoadedFor] reads
  /// again once [retryDelay] has passed.
  final _loadFailedAt = <String, DateTime>{};

  /// When each viewer's last read succeeded: [ensureLoadedFor] reads again
  /// once [refreshAfter] has passed.
  final _loadedAt = <String, DateTime>{};

  /// Per viewer, the number of server answers asked for so far and of the
  /// latest one applied: an answer to an older request is not applied over a
  /// newer one.
  final _asked = <String, int>{};
  final _applied = <String, int>{};

  /// Dismissals the server has not taken yet, per viewer; sent again on the
  /// next [ensureLoadedFor] or [dismiss].
  final _pending = <String, Set<String>>{};

  final _loading = <String, Future<void>>{};

  /// The flush running per viewer; callers meanwhile share it.
  final _flushing = <String, Future<void>>{};

  bool isDismissed({required String viewerId, required String beaconId}) =>
      _keys.contains(keyFor(viewerId: viewerId, beaconId: beaconId));

  /// Whether the sub-card may show: only once the account's dismissals are
  /// known, so one dismissed on another device does not flash here first.
  bool shouldShow({required String viewerId, required String beaconId}) =>
      _known.contains(viewerId) &&
      !isDismissed(viewerId: viewerId, beaconId: beaconId);

  /// Reads [viewerId]'s dismissals, and again once [refreshAfter] has passed,
  /// so dismissals made on another device reach an open one. After a failed
  /// read the sub-card shows (the safe default) and a call after [retryDelay]
  /// reads again; it also re-sends dismissals the server has not taken yet.
  /// Called from every sub-card build, so it starts at most one read and one
  /// flush at a time.
  Future<void> ensureLoadedFor(String viewerId) {
    if (viewerId.isEmpty) return Future.value();
    final loading = _loading[viewerId];
    if (loading != null) return loading;
    final failedAt = _loadFailedAt[viewerId];
    if (failedAt != null) {
      if (clock().difference(failedAt) < retryDelay) return Future.value();
    } else if (_known.contains(viewerId) &&
        clock().difference(_loadedAt[viewerId]!) < refreshAfter) {
      return _flushPending(viewerId);
    }
    return _loading[viewerId] = _load(viewerId);
  }

  /// Hides the sub-card at once, then records it for the account.
  Future<void> dismiss({
    required String viewerId,
    required String beaconId,
  }) async {
    if (_keys.add(keyFor(viewerId: viewerId, beaconId: beaconId))) {
      notifyListeners();
    }
    (_pending[viewerId] ??= {}).add(beaconId);
    await _flushPending(viewerId);
  }

  /// Sends every not-yet-recorded dismissal of [viewerId], one flush at a
  /// time; a call while one runs shares it. One that failed on the way stays
  /// pending (and hidden here) for the next try; one the server refused is
  /// dropped (hidden here until the server's next answer).
  Future<void> _flushPending(String viewerId) {
    final pending = _pending[viewerId];
    if (pending == null || pending.isEmpty) return Future.value();
    return _flushing[viewerId] ??= _flush(viewerId, pending).whenComplete(() {
      // The entry is this flush's own future: drop it, don't await it.
      _flushing.remove(viewerId)?.ignore();
    });
  }

  Future<void> _flush(String viewerId, Set<String> pending) async {
    // A × tapped while this runs joins this flush, so keep going until
    // every dismissal it can see has been tried once.
    final tried = <String>{};
    for (
      var next = pending.difference(tried);
      next.isNotEmpty;
      next = pending.difference(tried)
    ) {
      final beaconId = next.first;
      tried.add(beaconId);
      final asked = _ask(viewerId);
      try {
        final held = await _port.dismiss(
          viewerId: viewerId,
          beaconId: beaconId,
        );
        pending.remove(beaconId);
        _apply(viewerId, held, asked);
      } on OfferAcceptedDismissalRefusedException {
        pending.remove(beaconId);
      } on Object catch (_) {
        // Offline or busy: kept for the next try.
      }
    }
  }

  Future<void> _load(String viewerId) async {
    try {
      final asked = _ask(viewerId);
      _apply(viewerId, await _port.load(viewerId: viewerId), asked);
      _loadFailedAt.remove(viewerId);
      _loadedAt[viewerId] = clock();
      await _flushPending(viewerId);
    } on Object catch (_) {
      // Nothing known is the safe default: the sub-card shows; read again
      // once retryDelay has passed.
      _loadFailedAt[viewerId] = clock();
    } finally {
      _known.add(viewerId);
      // The entry is this load's own future: drop it, don't await it.
      _loading.remove(viewerId)?.ignore();
      notifyListeners();
    }
  }

  int _ask(String viewerId) => _asked[viewerId] = (_asked[viewerId] ?? 0) + 1;

  /// Takes the server's list of [viewerId]'s dismissals as the truth, keeping
  /// those it has not taken yet: the server deletes a dismissal when the
  /// helper withdraws or is removed, so a later acceptance shows again.
  void _apply(String viewerId, Set<String> beaconIds, int asked) {
    if (asked < (_applied[viewerId] ?? 0)) return;
    _applied[viewerId] = asked;
    final prefix = keyFor(viewerId: viewerId, beaconId: '');
    final next = {
      for (final b in {...beaconIds, ...?_pending[viewerId]})
        keyFor(viewerId: viewerId, beaconId: b),
    };
    final current = {..._keys.where((k) => k.startsWith(prefix))};
    if (current.length == next.length && current.containsAll(next)) return;
    _keys
      ..removeAll(current)
      ..addAll(next);
    notifyListeners();
  }
}
