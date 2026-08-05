import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';

typedef CommitmentRecordCall = ({
  String beaconId,
  String userId,
  String actorUserId,
  CommitmentEventKind kind,
  String? reason,
});

String commitmentPairKey(String beaconId, String userId) => '$beaconId:$userId';

/// Records [record] calls and serves configurable prior events for query tests.
final class RecordingCommitmentRepository extends Fake
    implements CommitmentRepositoryPort {
  RecordingCommitmentRepository({
    Map<String, List<CommitmentEvent>> eventsByPair = const {},
    DateTime? initialClock,
  }) : _eventsByPair = {
          for (final entry in eventsByPair.entries)
            entry.key: List<CommitmentEvent>.from(entry.value),
        },
        _clock = initialClock ?? DateTime.utc(2026);

  final recordCalls = <CommitmentRecordCall>[];
  final Map<String, List<CommitmentEvent>> _eventsByPair;
  var _nextSeq = 1;
  DateTime _clock;

  DateTime get clock => _clock;

  void advanceClock(Duration duration) {
    _clock = _clock.add(duration);
  }

  void setClock(DateTime value) {
    _clock = value;
  }

  void seedEvents({
    required String beaconId,
    required String userId,
    required List<CommitmentEvent> events,
  }) {
    _eventsByPair[commitmentPairKey(beaconId, userId)] =
        List<CommitmentEvent>.from(events);
  }

  @override
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  }) async {
    recordCalls.add(
      (
        beaconId: beaconId,
        userId: userId,
        actorUserId: actorUserId,
        kind: kind,
        reason: reason,
      ),
    );
    final key = commitmentPairKey(beaconId, userId);
    final events = _eventsByPair.putIfAbsent(key, () => []);
    events.add(
      CommitmentEvent(
        id: 'CE-test-${_nextSeq}',
        seq: _nextSeq++,
        beaconId: beaconId,
        userId: userId,
        actorUserId: actorUserId,
        kind: kind,
        reason: reason,
        createdAt: _clock,
      ),
    );
  }

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async {
    final result = <String, List<CommitmentEvent>>{};
    for (final entry in _eventsByPair.entries) {
      final parts = entry.key.split(':');
      if (parts.first != beaconId) continue;
      result[parts.last] = List<CommitmentEvent>.from(entry.value);
    }
    return result;
  }

  @override
  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  }) async =>
      List<CommitmentEvent>.from(
        _eventsByPair[commitmentPairKey(beaconId, userId)] ?? const [],
      );
}

/// Commitment port that ignores all writes and returns empty history.
final class NoOpCommitmentRepository extends Fake
    implements CommitmentRepositoryPort {
  @override
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  }) async {}

  @override
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(
    String beaconId,
  ) async =>
      {};

  @override
  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  }) async =>
      [];
}
