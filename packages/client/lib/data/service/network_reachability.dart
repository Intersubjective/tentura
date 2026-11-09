import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';

import 'network_reachability_browser_stub.dart'
    if (dart.library.js_interop) 'network_reachability_browser_web.dart';

/// Answers `true` when the server could be reached.
typedef ReachabilityProbe = Future<bool> Function();

/// Whether the app can currently reach the network (#513).
///
/// Fed by the HTTP client (a transport failure means offline, any answer from
/// the server means online) and by the browser's own online/offline signal,
/// so the app can say it is offline even while the live socket has not
/// noticed yet.
///
/// While offline it probes the server itself (#1110), backing off from
/// [probeFirstDelay] to [probeMaxDelay], so the app comes back online even
/// when no other request is in flight. Probing stops once online.
@singleton
class NetworkReachability implements NetworkReachabilityPort {
  NetworkReachability()
    : this._(
        _probeServer,
        initialOnline: browserInitiallyOnline(),
        browserOnline: browserOnlineChanges(),
      );

  /// With no [probe] the service never probes on its own.
  @visibleForTesting
  NetworkReachability.forTesting({
    Stream<bool>? browserOnline,
    ReachabilityProbe? probe,
  }) : this._(probe, initialOnline: true, browserOnline: browserOnline);

  NetworkReachability._(
    this._probe, {
    required bool initialOnline,
    Stream<bool>? browserOnline,
  }) : _online = initialOnline {
    _browserSub = browserOnline?.listen(_setOnline);
    if (!initialOnline) _startProbing();
  }

  static const probeFirstDelay = Duration(seconds: 2);

  static const probeMaxDelay = Duration(seconds: 30);

  final _changes = StreamController<bool>.broadcast();
  final ReachabilityProbe? _probe;
  StreamSubscription<bool>? _browserSub;
  Timer? _probeTimer;

  /// Bumped on every stop, so a probe still in flight from an earlier
  /// offline period cannot schedule another.
  var _probeGeneration = 0;
  var _probeDelay = probeFirstDelay;
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
    if (online) {
      _stopProbing();
    } else {
      _startProbing();
    }
    _changes.add(online);
  }

  void _startProbing() {
    if (_probe == null) return;
    _stopProbing();
    _probeDelay = probeFirstDelay;
    _scheduleProbe();
  }

  void _stopProbing() {
    _probeGeneration++;
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  void _scheduleProbe() {
    final generation = _probeGeneration;
    _probeTimer = Timer(_probeDelay, () => unawaited(_runProbe(generation)));
  }

  Future<void> _runProbe(int generation) async {
    final probe = _probe;
    if (probe == null) return;
    bool reached;
    try {
      reached = await probe();
    } on Object {
      reached = false;
    }
    // Online meanwhile (another request answered), or disposed.
    if (generation != _probeGeneration || _changes.isClosed) return;
    if (reached) {
      _setOnline(true);
      return;
    }
    final doubled = _probeDelay * 2;
    _probeDelay = doubled > probeMaxDelay ? probeMaxDelay : doubled;
    _scheduleProbe();
  }

  @disposeMethod
  Future<void> dispose() async {
    _stopProbing();
    await _browserSub?.cancel();
    await _changes.close();
  }
}

/// Any HTTP answer from the API endpoint (even an error status) means the
/// server was reached, the same rule the HTTP client reports by.
Future<bool> _probeServer() async {
  final client = http.Client();
  try {
    await client
        .get(Uri.parse(kServerName + kPathGraphQLEndpointV2))
        .timeout(const Duration(seconds: kRequestTimeout));
    return true;
  } on Object {
    return false;
  } finally {
    client.close();
  }
}
