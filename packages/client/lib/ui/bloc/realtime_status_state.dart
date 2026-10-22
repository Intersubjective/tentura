import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';

final class RealtimeStatusState {
  const RealtimeStatusState({
    this.phase = RealtimeConnectionPhase.unbound,
    this.showPausedBanner = false,
    this.showOfflineBanner = false,
  });

  final RealtimeConnectionPhase phase;
  final bool showPausedBanner;

  /// The network is unreachable (a request failed on transport or the browser
  /// reports offline), whatever the live socket says (#513).
  final bool showOfflineBanner;
}
