import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

/// Where the dismissed «offer accepted» sub-cards are kept between sessions.
abstract interface class OfferAcceptedDismissalPort {
  Future<Set<String>> load();

  Future<void> save(Set<String> keys);
}

/// Keeps nothing between sessions; the fallback where no store is wired
/// (tests, previews).
final class InMemoryOfferAcceptedDismissalPort
    implements OfferAcceptedDismissalPort {
  Set<String> _keys = {};

  @override
  Future<Set<String>> load() async => {..._keys};

  @override
  Future<void> save(Set<String> keys) async => _keys = {...keys};
}

/// B077 — which «your offer was accepted» event sub-cards the viewer has
/// dismissed with ×.
///
/// One dismissal per viewer and Request covers every place the sub-card is
/// shown (the Requests tab card and the Request's People tab), and it is
/// remembered across sessions through [OfferAcceptedDismissalPort].
@Singleton(env: [Environment.dev, Environment.prod])
class OfferAcceptedDismissals extends ChangeNotifier {
  OfferAcceptedDismissals(this._port) {
    ready = _load();
  }

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

  /// Completes once the remembered dismissals are loaded.
  late final Future<void> ready;

  bool isDismissed({required String viewerId, required String beaconId}) =>
      _keys.contains(keyFor(viewerId: viewerId, beaconId: beaconId));

  /// Hides the sub-card at once, then remembers it.
  Future<void> dismiss({
    required String viewerId,
    required String beaconId,
  }) async {
    if (!_keys.add(keyFor(viewerId: viewerId, beaconId: beaconId))) return;
    notifyListeners();
    // Saving before the load finished would overwrite what was remembered.
    if (!_loaded) await ready;
    await _port.save({..._keys});
  }

  var _loaded = false;

  Future<void> _load() async {
    try {
      final loaded = await _port.load();
      if (loaded.isNotEmpty) {
        _keys.addAll(loaded);
        notifyListeners();
      }
    } on Object catch (_) {
      // Nothing remembered is the safe default: the sub-card shows again.
    } finally {
      _loaded = true;
    }
  }
}
