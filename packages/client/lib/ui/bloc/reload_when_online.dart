import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/network_reachability_port.dart';

/// Reloads a screen whose last load failed when the app comes back online
/// (#1110), the way its «Try again» does: once per offline→online
/// transition, and never for a screen whose last load succeeded.
final class ReloadWhenOnline {
  ReloadWhenOnline({
    required bool Function() lastLoadFailed,
    required void Function() reload,
    NetworkReachabilityPort? reachability,
  }) {
    final port =
        reachability ??
        (GetIt.I.isRegistered<NetworkReachabilityPort>()
            ? GetIt.I<NetworkReachabilityPort>()
            : null);
    _onlineChanges = port?.onlineChanges.where((online) => online).listen((_) {
      if (lastLoadFailed()) reload();
    });
  }

  StreamSubscription<bool>? _onlineChanges;

  Future<void> close() async => _onlineChanges?.cancel();
}
