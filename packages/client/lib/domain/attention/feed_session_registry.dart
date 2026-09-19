import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'entity/attention_feed.dart';

/// Account-scoped feed view/search/page state keyed by [AttentionFeedDestinationId].
@lazySingleton
final class FeedSessionRegistry {
  final Map<String, AttentionFeedSession> _sessions = {};
  final Map<String, BehaviorSubject<AttentionFeedSession>> _streams = {};
  final Map<String, int> _attachCounts = {};

  Iterable<String> get attachedDestinationIds => _attachCounts.entries
      .where((entry) => entry.value > 0)
      .map((entry) => entry.key);

  AttentionFeedSession attach(String destinationId) {
    _attachCounts[destinationId] = (_attachCounts[destinationId] ?? 0) + 1;
    return _ensureSession(destinationId);
  }

  void detach(String destinationId) {
    final count = _attachCounts[destinationId] ?? 0;
    if (count <= 1) {
      _attachCounts.remove(destinationId);
    } else {
      _attachCounts[destinationId] = count - 1;
    }
  }

  void resetForAccount() {
    final attached = attachedDestinationIds.toList(growable: false);
    for (final controller in _streams.values) {
      controller.close();
    }
    _sessions.clear();
    _streams.clear();
    for (final destinationId in attached) {
      _ensureSession(destinationId, const AttentionFeedSession());
    }
  }

  AttentionFeedSession session(String destinationId) =>
      _sessions[destinationId] ?? const AttentionFeedSession();

  Stream<AttentionFeedSession> watch(String destinationId) {
    _ensureSession(destinationId);
    return _streams[destinationId]!.stream;
  }

  void update(String destinationId, AttentionFeedSession next) {
    _ensureSession(destinationId);
    _sessions[destinationId] = next;
    final controller = _streams[destinationId];
    if (controller != null && !controller.isClosed) {
      controller.add(next);
    }
  }

  /// Commits several sessions as **one** move: every session is in place
  /// before any listener is notified, so no observer can see a Request
  /// already dropped by one destination and not yet gained by another.
  void updateAll(Map<String, AttentionFeedSession> next) {
    for (final entry in next.entries) {
      _ensureSession(entry.key);
      _sessions[entry.key] = entry.value;
    }
    for (final entry in next.entries) {
      final controller = _streams[entry.key];
      if (controller != null && !controller.isClosed) {
        controller.add(entry.value);
      }
    }
  }

  AttentionFeedSession _ensureSession(
    String destinationId, [
    AttentionFeedSession? seed,
  ]) {
    if (_sessions.containsKey(destinationId)) {
      return _sessions[destinationId]!;
    }
    final initial = seed ?? const AttentionFeedSession();
    _sessions[destinationId] = initial;
    _streams[destinationId] = BehaviorSubject<AttentionFeedSession>.seeded(
      initial,
    );
    return initial;
  }
}
