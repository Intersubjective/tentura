import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/constellation_anchor.dart';
import '../entity/constellation_anchor_projection.dart';
import '../port/constellation_anchor_repository_port.dart';
import '../port/constellation_repository_port.dart';

enum ConstellationAnchorWriteKind { upsert, delete }

@immutable
final class ConstellationAnchorPendingWrite {
  const ConstellationAnchorPendingWrite.upsert({
    required this.target,
    required this.position,
  }) : kind = ConstellationAnchorWriteKind.upsert;

  const ConstellationAnchorPendingWrite.delete({required this.target})
    : kind = ConstellationAnchorWriteKind.delete,
      position = null;

  final ConstellationAnchorWriteKind kind;
  final ConstellationAnchorTarget target;
  final ConstellationAnchorPosition? position;
}

enum ConstellationAnchorWriteOutcomeKind {
  succeeded,
  failed,
  staleResponseDiscarded,
}

@immutable
final class ConstellationAnchorWriteOutcome {
  const ConstellationAnchorWriteOutcome({
    required this.kind,
    this.projection,
    this.failureMessage,
  });

  final ConstellationAnchorWriteOutcomeKind kind;
  final ConstellationAnchorProjection? projection;
  final String? failureMessage;
}

@immutable
final class ConstellationAnchorsRefreshResult {
  const ConstellationAnchorsRefreshResult({
    required this.projection,
    required this.applied,
  });

  final ConstellationAnchorProjection projection;
  final bool applied;
}

/// Screen-scoped anchor writes, confirmed cache, and private realtime catch-up.
@Order(2)
@singleton
final class ConstellationAnchorCase extends UseCaseBase {
  ConstellationAnchorCase(
    this._fieldRepository,
    this._anchorRepository,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  });

  final ConstellationRepositoryPort _fieldRepository;
  final ConstellationAnchorRepositoryPort _anchorRepository;
  final RealtimeSyncCase _realtimeSyncCase;

  StreamSubscription<RealtimeEntityChange>? _changeSub;
  StreamSubscription<RealtimeCatchUp>? _catchUpSub;

  String _viewerAccountId = '';
  int _loadGeneration = 0;
  bool _screenActive = false;
  bool _syncPending = false;

  ConstellationAnchorProjection _confirmed =
      ConstellationAnchorProjection.empty;

  ConstellationFieldMembershipFilters _membershipFilters =
      ConstellationFieldMembershipFilters.defaults;

  Future<void>? _anchorsRefreshInFlight;
  bool _anchorsRefreshQueued = false;

  ConstellationAnchorPendingWrite? _pendingWrite;
  int _writeCount = 0;
  int _anchorsFetchCount = 0;

  final _refreshController = StreamController<void>.broadcast();

  Stream<void> get refreshSignals => _refreshController.stream;

  ConstellationAnchorProjection get confirmedProjection => _confirmed;

  ConstellationAnchorRevision get projectionRevision => _confirmed.revision;

  bool get syncPending => _syncPending;

  bool get hasPendingWrite => _pendingWrite != null;

  ConstellationAnchorTarget? get pendingWriteTarget => _pendingWrite?.target;

  @visibleForTesting
  int get writeCount => _writeCount;

  @visibleForTesting
  int get anchorsFetchCount => _anchorsFetchCount;

  /// Subscribe before the initial FULL load (C7 / C8 screen lifecycle).
  void activate({required String viewerAccountId}) {
    if (_screenActive && _viewerAccountId == viewerAccountId) {
      return;
    }
    deactivate();
    _viewerAccountId = viewerAccountId;
    _screenActive = true;
    if (_loadGeneration == 0) {
      _loadGeneration = 1;
    }
    _changeSub = _realtimeSyncCase
        .changesForAggregate(
          kinds: const {RealtimeEntityKind.constellationAnchor},
          aggregateId: viewerAccountId,
        )
        .listen((_) => _scheduleAnchorsRefresh(), cancelOnError: false);
    _catchUpSub = _realtimeSyncCase.catchUps.listen(
      (_) => unawaited(_refreshAnchorsOnce()),
      cancelOnError: false,
    );
  }

  void deactivate() {
    _screenActive = false;
    _viewerAccountId = '';
    _pendingWrite = null;
    _anchorsRefreshQueued = false;
    _anchorsRefreshInFlight = null;
    unawaited(_changeSub?.cancel());
    unawaited(_catchUpSub?.cancel());
    _changeSub = null;
    _catchUpSub = null;
  }

  /// Bumps load generation once and clears prior-account anchor state.
  int onAccountChanged() {
    _confirmed = ConstellationAnchorProjection.empty;
    _syncPending = false;
    _pendingWrite = null;
    _membershipFilters = ConstellationFieldMembershipFilters.defaults;
    return ++_loadGeneration;
  }

  void bindLoadGeneration(int generation) {
    _loadGeneration = generation;
  }

  int bumpLoadGeneration() => ++_loadGeneration;

  void syncMembershipFilters(ConstellationFieldMembershipFilters filters) {
    _membershipFilters = filters;
  }

  /// Seeds the confirmed cache from an accepted FULL snapshot.
  bool adoptConfirmedProjection(ConstellationAnchorProjection projection) {
    if (projection.revision.compareTo(_confirmed.revision) < 0) {
      return false;
    }
    _confirmed = projection;
    _syncPending = false;
    return true;
  }

  /// Applies an ANCHORS-only fetch when [generation] still matches.
  Future<ConstellationAnchorsRefreshResult?> refreshAnchors({
    required int generation,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    if (!_screenActive || generation != _loadGeneration) {
      return null;
    }
    final projection = await _fetchAnchorsProjection(
      membershipFilters: membershipFilters,
    );
    if (!_screenActive || generation != _loadGeneration) {
      return null;
    }
    final applied = _applyIncomingProjection(projection);
    if (applied) {
      _refreshController.add(null);
    }
    return ConstellationAnchorsRefreshResult(
      projection: _confirmed,
      applied: applied,
    );
  }

  Future<ConstellationAnchorWriteOutcome> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
    required int generation,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    return _runWrite(
      generation: generation,
      membershipFilters: membershipFilters,
      pending: ConstellationAnchorPendingWrite.upsert(
        target: target,
        position: position,
      ),
      action: () => _anchorRepository.upsert(
        target: target,
        position: position,
      ),
      adoptMutation: (result) {
        if (result.revision.compareTo(_confirmed.revision) < 0) {
          return false;
        }
        _upsertConfirmedAnchor(result.anchor);
        _confirmed = ConstellationAnchorProjection(
          revision: result.revision,
          anchors: _confirmed.anchors,
          pinnedPeers: _confirmed.pinnedPeers,
          pinnedRequests: _confirmed.pinnedRequests,
          supportPeers: _confirmed.supportPeers,
          supportEdges: _confirmed.supportEdges,
          serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
          serverFilteredBeaconCount: _confirmed.serverFilteredBeaconCount,
        );
        return true;
      },
    );
  }

  Future<ConstellationAnchorWriteOutcome> deleteAnchor({
    required ConstellationAnchorTarget target,
    required int generation,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    return _runWrite(
      generation: generation,
      membershipFilters: membershipFilters,
      pending: ConstellationAnchorPendingWrite.delete(target: target),
      action: () => _anchorRepository.delete(target: target),
      adoptMutation: (result) {
        if (result.revision.compareTo(_confirmed.revision) < 0) {
          return false;
        }
        _removeConfirmedAnchor(result.target);
        _confirmed = ConstellationAnchorProjection(
          revision: result.revision,
          anchors: _confirmed.anchors,
          pinnedPeers: _confirmed.pinnedPeers,
          pinnedRequests: _confirmed.pinnedRequests,
          supportPeers: _confirmed.supportPeers,
          supportEdges: _confirmed.supportEdges,
          serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
          serverFilteredBeaconCount: _confirmed.serverFilteredBeaconCount,
        );
        return true;
      },
    );
  }

  Future<ConstellationAnchorWriteOutcome> _runWrite<T>({
    required int generation,
    required ConstellationFieldMembershipFilters membershipFilters,
    required ConstellationAnchorPendingWrite pending,
    required Future<T> Function() action,
    required bool Function(T result) adoptMutation,
  }) async {
    if (!_screenActive || generation != _loadGeneration) {
      return const ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
      );
    }
    _pendingWrite = pending;
    _writeCount++;
    try {
      final mutation = await action();
      if (!_screenActive || generation != _loadGeneration) {
        return const ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
        );
      }
      final adopted = adoptMutation(mutation);
      if (!adopted) {
        await _refreshAnchorsOnce(
          membershipFilters: membershipFilters,
        );
        return ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          projection: _confirmed,
        );
      }
      await _refreshAnchorsOnce(membershipFilters: membershipFilters);
      _syncPending = false;
      return ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.succeeded,
        projection: _confirmed,
      );
    } on Object catch (error, stackTrace) {
      logger.warning('Constellation anchor write failed', error, stackTrace);
      if (!_screenActive || generation != _loadGeneration) {
        return const ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
        );
      }
      await _refreshAnchorsOnce(membershipFilters: membershipFilters);
      _syncPending = true;
      return ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.failed,
        projection: _confirmed,
        failureMessage: 'Could not save constellation placement.',
      );
    } finally {
      if (identical(_pendingWrite, pending)) {
        _pendingWrite = null;
      }
    }
  }

  /// Updates confirmed cache; equal revisions may refresh membership (C7).
  bool applyIncomingProjection(
    ConstellationAnchorProjection incoming, {
    required int generation,
  }) {
    if (!_screenActive || generation != _loadGeneration) {
      return false;
    }
    return _applyIncomingProjection(incoming);
  }

  bool _applyIncomingProjection(ConstellationAnchorProjection incoming) {
    final comparison = incoming.revision.compareTo(_confirmed.revision);
    if (comparison < 0) {
      return false;
    }
    _confirmed = incoming;
    _syncPending = false;
    return true;
  }

  void _upsertConfirmedAnchor(ConstellationAnchor anchor) {
    final anchors = [
      for (final existing in _confirmed.anchors)
        if (existing.target != anchor.target) existing,
      anchor,
    ]..sort(ConstellationAnchor.comparePaintOrder);
    _confirmed = ConstellationAnchorProjection(
      revision: anchor.revision,
      anchors: anchors,
      pinnedPeers: _confirmed.pinnedPeers,
      pinnedRequests: _confirmed.pinnedRequests,
      supportPeers: _confirmed.supportPeers,
      supportEdges: _confirmed.supportEdges,
      serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
      serverFilteredBeaconCount: _confirmed.serverFilteredBeaconCount,
    );
  }

  void _removeConfirmedAnchor(ConstellationAnchorTarget target) {
    _confirmed = ConstellationAnchorProjection(
      revision: _confirmed.revision,
      anchors: [
        for (final anchor in _confirmed.anchors)
          if (anchor.target != target) anchor,
      ],
      pinnedPeers: [
        for (final peer in _confirmed.pinnedPeers)
          if (peer.id != target.id ||
              target.kind != ConstellationAnchorTargetKind.person)
            peer,
      ],
      pinnedRequests: [
        for (final request in _confirmed.pinnedRequests)
          if (request.id != target.id ||
              target.kind != ConstellationAnchorTargetKind.beacon)
            request,
      ],
      supportPeers: _confirmed.supportPeers,
      supportEdges: _confirmed.supportEdges,
      serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
      serverFilteredBeaconCount: _confirmed.serverFilteredBeaconCount,
    );
  }

  void _scheduleAnchorsRefresh() {
    if (!_screenActive) {
      return;
    }
    unawaited(_refreshAnchorsOnce(membershipFilters: _membershipFilters));
  }

  Future<void> _refreshAnchorsOnce({
    ConstellationFieldMembershipFilters? membershipFilters,
  }) async {
    final resolvedFilters = membershipFilters ?? _membershipFilters;
    final inFlight = _anchorsRefreshInFlight;
    if (inFlight != null) {
      _anchorsRefreshQueued = true;
      return inFlight;
    }
    final generation = _loadGeneration;
    late final Future<void> future;
    future = _runAnchorsRefreshLoop(
      generation: generation,
      membershipFilters: resolvedFilters,
    ).whenComplete(() {
      if (identical(_anchorsRefreshInFlight, future)) {
        _anchorsRefreshInFlight = null;
      }
    });
    _anchorsRefreshInFlight = future;
    return future;
  }

  Future<void> _runAnchorsRefreshLoop({
    required int generation,
    required ConstellationFieldMembershipFilters membershipFilters,
  }) async {
    do {
      _anchorsRefreshQueued = false;
      if (!_screenActive || generation != _loadGeneration) {
        return;
      }
      final projection = await _fetchAnchorsProjection(
        membershipFilters: membershipFilters,
      );
      if (!_screenActive || generation != _loadGeneration) {
        return;
      }
      if (_applyIncomingProjection(projection)) {
        _refreshController.add(null);
      }
    } while (_anchorsRefreshQueued && _screenActive && generation == _loadGeneration);
  }

  Future<ConstellationAnchorProjection> _fetchAnchorsProjection({
    required ConstellationFieldMembershipFilters membershipFilters,
  }) async {
    _anchorsFetchCount++;
    final field = await _fieldRepository.fetch(
      membershipFilters: membershipFilters,
      projection: ConstellationProjection.anchors,
    );
    return field.resolvedAnchorProjection;
  }

  @disposeMethod
  Future<void> dispose() async {
    deactivate();
    await _refreshController.close();
  }
}
