import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';

enum DebugSendChannel {
  fcm,
  email,
}

/// Per-user, per-channel throttle for debug test sends (in-memory, per process).
@singleton
final class DebugSendRateLimiter {
  DebugSendRateLimiter() : _cooldown = const Duration(seconds: 10);

  @visibleForTesting
  DebugSendRateLimiter.withCooldown(Duration cooldown) : _cooldown = cooldown;

  final Duration _cooldown;

  final _lastAcquire = <String, DateTime>{};

  bool tryAcquire(String userId, DebugSendChannel channel) {
    if (userId.isEmpty) {
      return false;
    }
    final key = '$userId:${channel.name}';
    final now = DateTime.timestamp();
    final last = _lastAcquire[key];
    if (last != null && now.difference(last) < _cooldown) {
      return false;
    }
    _lastAcquire[key] = now;
    return true;
  }

  @visibleForTesting
  void clear() => _lastAcquire.clear();
}
