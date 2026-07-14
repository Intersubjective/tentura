import 'package:freezed_annotation/freezed_annotation.dart';

part 'realtime_connection_status.freezed.dart';

enum RealtimeConnectionPhase {
  unbound,
  connecting,
  authenticating,
  authenticated,
  disconnected,
}

@freezed
abstract class RealtimeConnectionStatus with _$RealtimeConnectionStatus {
  const factory RealtimeConnectionStatus({
    required int connectionEpoch,
    required RealtimeConnectionPhase phase,
    String? accountId,
  }) = _RealtimeConnectionStatus;

  const RealtimeConnectionStatus._();

  bool get isAuthenticated => phase == RealtimeConnectionPhase.authenticated;
}
