import 'package:meta/meta.dart';

enum RealtimeTransportPhase {
  unbound,
  connecting,
  authenticating,
  authenticated,
  disconnected,
}

enum RealtimeReconnectCause {
  initial,
  network,
  pongTimeout,
  authenticationFailure,
  terminalSocket,
}

@immutable
final class RealtimeTransportStatus {
  const RealtimeTransportStatus({
    required this.accountId,
    required this.connectionEpoch,
    required this.phase,
    required this.cause,
  });

  const RealtimeTransportStatus.unbound({required int connectionEpoch})
    : this(
        accountId: null,
        connectionEpoch: connectionEpoch,
        phase: RealtimeTransportPhase.unbound,
        cause: RealtimeReconnectCause.initial,
      );

  final String? accountId;
  final int connectionEpoch;
  final RealtimeTransportPhase phase;
  final RealtimeReconnectCause cause;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealtimeTransportStatus &&
          accountId == other.accountId &&
          connectionEpoch == other.connectionEpoch &&
          phase == other.phase &&
          cause == other.cause;

  @override
  int get hashCode => Object.hash(accountId, connectionEpoch, phase, cause);
}
