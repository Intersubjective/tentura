import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';

final class RealtimeStatusState {
  const RealtimeStatusState({
    this.phase = RealtimeConnectionPhase.unbound,
    this.showPausedBanner = false,
  });

  final RealtimeConnectionPhase phase;
  final bool showPausedBanner;
}
