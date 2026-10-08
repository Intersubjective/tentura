import 'dart:async';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_field_repository_port.dart';

/// Holds snapshot reads open so overlap is controlled by the test, not timing.
final class GatedConstellationFieldRepository
    implements ConstellationFieldRepositoryPort {
  GatedConstellationFieldRepository({this.maxConcurrentReads});

  final int? maxConcurrentReads;
  final firstReadStarted = Completer<void>();
  final _pending =
      <
        ({
          Completer<ConstellationFieldSnapshot> result,
          String context,
          int generation,
        })
      >[];

  int readSnapshotCalls = 0;
  int activeReads = 0;
  final reads =
      <
        ({
          String viewerId,
          String context,
          ConstellationFieldReadParams params,
        })
      >[];

  /// Models committed field data; each read captures its own snapshot version.
  int visibleGeneration = 0;

  @override
  Future<ConstellationFieldSnapshot> readSnapshot({
    required String viewerId,
    required String context,
    required ConstellationFieldReadParams params,
  }) async {
    readSnapshotCalls++;
    reads.add((viewerId: viewerId, context: context, params: params));
    final limit = maxConcurrentReads;
    if (limit != null && activeReads >= limit) {
      throw StateError('Repository admission capacity exhausted');
    }
    activeReads++;
    final result = Completer<ConstellationFieldSnapshot>();
    _pending.add((
      result: result,
      context: context,
      generation: visibleGeneration,
    ));
    if (!firstReadStarted.isCompleted) firstReadStarted.complete();
    try {
      return await result.future;
    } finally {
      activeReads--;
    }
  }

  void completePendingReads() {
    final pending = List.of(_pending);
    _pending.clear();
    for (final read in pending) {
      read.result.complete(
        ConstellationFieldSnapshot(
          loadedAt: DateTime.utc(2026, 10, 8),
          context: read.context,
          peers: [ConstellationPeerRecord(id: 'generation-${read.generation}')],
          edges: const [],
          requests: const [],
          peersCapped: false,
          requestsCapped: false,
        ),
      );
    }
  }

  @override
  Future<({Set<String> ids, bool capped})> visibleGraphPeerIds({
    required String viewerId,
    required String context,
    required int cap,
  }) => throw UnsupportedError('Use the snapshot boundary');

  @override
  Future<List<ConstellationEdgeRecord>> trustEdges({
    required String viewerId,
    required String context,
    required Set<String> nodeIds,
  }) => throw UnsupportedError('Use the snapshot boundary');

  @override
  Future<List<ConstellationRequestRecord>> ownRequests({
    required String viewerId,
  }) => throw UnsupportedError('Use the snapshot boundary');

  @override
  Future<List<ConstellationRequestRecord>> discoverableRequests({
    required String viewerId,
    required String context,
    required int cap,
  }) => throw UnsupportedError('Use the snapshot boundary');

  @override
  Future<List<ConstellationPeerRecord>> peerProfiles({
    required Set<String> ids,
  }) => throw UnsupportedError('Use the snapshot boundary');
}
