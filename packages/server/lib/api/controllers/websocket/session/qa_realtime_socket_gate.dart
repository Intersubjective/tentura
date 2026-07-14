import 'package:injectable/injectable.dart';

/// Isolate-local QA gate used to create a deterministic WebSocket outage.
///
/// The production route is absent unless QA auth is enabled. Keeping the gate
/// independent from the domain protocol makes suspension a transport-harness
/// concern and lets every server worker own only its local sessions.
@singleton
final class QaRealtimeSocketGate {
  final _bootstrappedUserIds = <String>{};
  final _suspendedUserIds = <String>{};
  final _userIdBySession = <Object, String>{};
  final _closersByUserId = <String, Map<Object, Future<void> Function()>>{};

  void registerBootstrappedUser(String userId) {
    _bootstrappedUserIds.add(userId);
  }

  bool wasBootstrapped(String userId) => _bootstrappedUserIds.contains(userId);

  bool isAuthenticationSuspended(String userId) =>
      _suspendedUserIds.contains(userId);

  void registerSession({
    required String userId,
    required Object session,
    required Future<void> Function() close,
  }) {
    unregisterSession(session);
    _userIdBySession[session] = userId;
    (_closersByUserId[userId] ??= {})[session] = close;
  }

  void unregisterSession(Object session) {
    final userId = _userIdBySession.remove(session);
    if (userId == null) return;
    final closers = _closersByUserId[userId];
    closers?.remove(session);
    if (closers?.isEmpty ?? false) {
      _closersByUserId.remove(userId);
    }
  }

  Future<int> suspendAndClose(String userId) async {
    _suspendedUserIds.add(userId);
    final closers = [...?_closersByUserId[userId]?.values];
    await Future.wait([
      for (final close in closers) close(),
    ]);
    return closers.length;
  }

  void resume(String userId) {
    _suspendedUserIds.remove(userId);
  }
}
