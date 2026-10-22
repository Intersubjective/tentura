import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/domain/port/network_reachability_port.dart';

import 'network_reachability_browser_stub.dart'
    if (dart.library.js_interop) 'network_reachability_browser_web.dart';

/// Whether the app can currently reach the network (#513).
///
/// Fed by the HTTP client (a transport failure means offline, any answer from
/// the server means online) and by the browser's own online/offline signal,
/// so the app can say it is offline even while the live socket has not
/// noticed yet.
@singleton
class NetworkReachability implements NetworkReachabilityPort {
  NetworkReachability()
    : this._(
        initialOnline: browserInitiallyOnline(),
        browserOnline: browserOnlineChanges(),
      );

  @visibleForTesting
  NetworkReachability.forTesting({Stream<bool>? browserOnline})
    : this._(initialOnline: true, browserOnline: browserOnline);

  NetworkReachability._({
    required bool initialOnline,
    Stream<bool>? browserOnline,
  }) : _online = initialOnline {
    _browserSub = browserOnline?.listen(_setOnline);
  }

  final _changes = StreamController<bool>.broadcast();
  StreamSubscription<bool>? _browserSub;
  bool _online;

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  /// A request could not reach the server (no network, DNS, timeout, ...).
  void reportTransportFailure() => _setOnline(false);

  /// The server answered a request (with data or with its own error).
  void reportSuccess() => _setOnline(true);

  void _setOnline(bool online) {
    if (online == _online || _changes.isClosed) return;
    _online = online;
    _changes.add(online);
  }

  @disposeMethod
  Future<void> dispose() async {
    await _browserSub?.cancel();
    await _changes.close();
  }
}
