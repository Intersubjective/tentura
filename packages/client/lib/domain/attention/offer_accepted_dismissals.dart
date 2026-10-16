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
  Future<Set<String>> dismiss({
    required String viewerId,
    required String beaconId,
  });
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

  static String keyFor({required String viewerId, required String beaconId}) =>
      '$viewerId:$beaconId';

  final OfferAcceptedDismissalPort _port;

  final _keys = <String>{};

  /// Viewers whose dismissals were read (or could not be read).
  final _known = <String>{};

  /// Viewers whose last read failed: the next [ensureLoadedFor] reads again.
  final _loadFailed = <String>{};

  /// Dismissals the server has not taken yet, per viewer; sent again on the
  /// next [ensureLoadedFor] or [dismiss].
  final _pending = <String, Set<String>>{};

  final _loading = <String, Future<void>>{};

  bool isDismissed({required String viewerId, required String beaconId}) =>
      _keys.contains(keyFor(viewerId: viewerId, beaconId: beaconId));

  /// Whether the sub-card may show: only once the account's dismissals are
  /// known, so one dismissed on another device does not flash here first.
  bool shouldShow({required String viewerId, required String beaconId}) =>
      _known.contains(viewerId) &&
      !isDismissed(viewerId: viewerId, beaconId: beaconId);

  /// Reads [viewerId]'s dismissals once per session. After a failed read the
  /// sub-card shows (the safe default) and the next call reads again; it
  /// also re-sends dismissals the server has not taken yet.
  Future<void> ensureLoadedFor(String viewerId) {
    if (viewerId.isEmpty) return Future.value();
    if (_known.contains(viewerId) && !_loadFailed.contains(viewerId)) {
      return _flushPending(viewerId);
    }
    return _loading[viewerId] ??= _load(viewerId);
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

  /// Sends every not-yet-recorded dismissal of [viewerId]; a failed one stays
  /// pending (and hidden here) for the next try.
  Future<void> _flushPending(String viewerId) async {
    final pending = _pending[viewerId];
    if (pending == null || pending.isEmpty) return;
    for (final beaconId in [...pending]) {
      try {
        _merge(
          viewerId,
          await _port.dismiss(viewerId: viewerId, beaconId: beaconId),
        );
        pending.remove(beaconId);
      } on Object catch (_) {
        // Offline or refused for now: kept for the next try.
      }
    }
  }

  Future<void> _load(String viewerId) async {
    try {
      _merge(viewerId, await _port.load(viewerId: viewerId));
      _loadFailed.remove(viewerId);
      await _flushPending(viewerId);
    } on Object catch (_) {
      // Nothing known is the safe default: the sub-card shows; read again
      // on the next ensureLoadedFor.
      _loadFailed.add(viewerId);
    } finally {
      _known.add(viewerId);
      // The entry is this load's own future: drop it, don't await it.
      _loading.remove(viewerId)?.ignore();
      notifyListeners();
    }
  }

  void _merge(String viewerId, Set<String> beaconIds) {
    final before = _keys.length;
    _keys.addAll([
      for (final b in beaconIds) keyFor(viewerId: viewerId, beaconId: b),
    ]);
    if (_keys.length != before) notifyListeners();
  }
}
