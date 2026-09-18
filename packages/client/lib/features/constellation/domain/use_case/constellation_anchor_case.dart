import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../constellation_drag_cluster.dart';
import '../entity/constellation_anchor.dart';
import '../entity/constellation_anchor_projection.dart';
import '../exception.dart';
import '../port/constellation_anchor_repository_port.dart';
import '../port/constellation_repository_port.dart';

enum ConstellationAnchorWriteKind { upsert, delete, clusterUpsert }

@immutable
final class ConstellationAnchorPendingWrite {
  const ConstellationAnchorPendingWrite.upsert({
    required this.target,
    required this.position,
  }) : kind = ConstellationAnchorWriteKind.upsert,
       companionPositions = null;

  const ConstellationAnchorPendingWrite.clusterUpsert({
    required this.target,
    required this.position,
    required this.companionPositions,
  }) : kind = ConstellationAnchorWriteKind.clusterUpsert;

  const ConstellationAnchorPendingWrite.delete({required this.target})
    : kind = ConstellationAnchorWriteKind.delete,
      position = null,
      companionPositions = null;

  final ConstellationAnchorWriteKind kind;
  final ConstellationAnchorTarget target;
  final ConstellationAnchorPosition? position;
  final Map<ConstellationAnchorTarget, ConstellationAnchorPosition>?
      companionPositions;

  Set<ConstellationAnchorTarget> get targetSet {
    final companions = companionPositions?.keys;
    if (companions == null || companions.isEmpty) {
      return {target};
    }
    return {target, ...companions};
  }
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
  ConstellationFieldMembershipFilters _queuedFilters =
      ConstellationFieldMembershipFilters.defaults;
  String _queuedAccountId = '';
  int _queuedLifecycleToken = 0;
  int _queuedRequestSeq = 0;
  int _anchorsRequestSeq = 0;
  int _lastAppliedRequestSeq = 0;

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

  Set<ConstellationAnchorTarget> get pendingWriteTargets =>
      _pendingWrite?.targetSet ?? const {};

  @visibleForTesting
  int get writeCount => _writeCount;

  @visibleForTesting
  int get anchorsFetchCount => _anchorsFetchCount;

  int get lifecycleToken => _loadGeneration;

  /// Subscribe before the initial FULL load (C7 / C8 screen lifecycle).
  int activate({required String viewerAccountId}) {
    if (viewerAccountId != _viewerAccountId) {
      _resetAccountOwnedState();
      _loadGeneration++;
    }
    if (_loadGeneration == 0) {
      _loadGeneration = 1;
    }
    _detachSubscriptions();
    _viewerAccountId = viewerAccountId;
    _screenActive = true;
    _attachSubscriptions();
    return _loadGeneration;
  }

  void deactivate({int? token}) {
    if (token != null && token != _loadGeneration) {
      return;
    }
    _screenActive = false;
    _detachSubscriptions();
  }

  /// Bumps load generation once and clears prior-account anchor state.
  int onAccountChanged() {
    _resetAccountOwnedState();
    return ++_loadGeneration;
  }

  void bindLoadGeneration(int generation) {
    if (generation > _loadGeneration) {
      _loadGeneration = generation;
    }
  }

  int bumpLoadGeneration() => ++_loadGeneration;

  void syncMembershipFilters(ConstellationFieldMembershipFilters filters) {
    _membershipFilters = filters;
  }

  void _resetAccountOwnedState() {
    _confirmed = ConstellationAnchorProjection.empty;
    _syncPending = false;
    _pendingWrite = null;
    _membershipFilters = ConstellationFieldMembershipFilters.defaults;
    _lastAppliedRequestSeq = 0;
  }

  void _attachSubscriptions() {
    final accountId = _viewerAccountId;
    _changeSub = _realtimeSyncCase
        .changesForAggregate(
          kinds: const {RealtimeEntityKind.constellationAnchor},
          aggregateId: accountId,
        )
        .listen((_) => _scheduleAnchorsRefresh(), cancelOnError: false);
    _catchUpSub = _realtimeSyncCase.catchUps.listen(
      (_) => unawaited(_refreshAnchorsOnce()),
      cancelOnError: false,
    );
  }

  void _detachSubscriptions() {
    unawaited(_changeSub?.cancel());
    unawaited(_catchUpSub?.cancel());
    _changeSub = null;
    _catchUpSub = null;
  }

  /// Seeds the confirmed cache from an accepted FULL snapshot.
  bool adoptConfirmedProjection(ConstellationAnchorProjection projection) {
    return _applyIncomingProjection(
      projection,
      requestSeq: ++_anchorsRequestSeq,
    );
  }

  /// Applies an ANCHORS-only fetch when [generation] still matches.
  Future<ConstellationAnchorsRefreshResult?> refreshAnchors({
    required int generation,
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    if (generation != _loadGeneration) {
      return null;
    }
    _membershipFilters = membershipFilters;
    await _refreshAnchorsOnce(membershipFilters: membershipFilters);
    if (generation != _loadGeneration) {
      return null;
    }
    return ConstellationAnchorsRefreshResult(
      projection: _confirmed,
      applied: true,
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

  /// One pending write: parent upsert first, then companions; abort companions
  /// when the parent mutation is not adopted. Final success uses recovery
  /// position match (not mutation revision alone).
  Future<ConstellationAnchorWriteOutcome> upsertAll({
    required ConstellationAnchorTarget parentTarget,
    required ConstellationAnchorPosition parentPosition,
    required List<({ConstellationAnchorTarget target, ConstellationAnchorPosition position})>
        companions,
    required int generation,
    Map<String, String> companionTitles = const {},
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    if (companions.isEmpty) {
      return upsert(
        target: parentTarget,
        position: parentPosition,
        generation: generation,
        membershipFilters: membershipFilters,
      );
    }
    if (generation != _loadGeneration || _pendingWrite != null) {
      return const ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
      );
    }
    final companionPositions = {
      for (final companion in companions)
        companion.target: companion.position,
    };
    final pending = ConstellationAnchorPendingWrite.clusterUpsert(
      target: parentTarget,
      position: parentPosition,
      companionPositions: companionPositions,
    );
    final writeAccount = _viewerAccountId;
    final writeToken = _loadGeneration;
    _pendingWrite = pending;
    _writeCount++;
    Object? mutationError;
    var parentAdopted = false;
    try {
      try {
        final parentResult = await _anchorRepository.upsert(
          target: parentTarget,
          position: parentPosition,
        );
        if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
          return const ConstellationAnchorWriteOutcome(
            kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          );
        }
        if (parentResult.revision.compareTo(_confirmed.revision) >= 0) {
          _upsertConfirmedAnchor(parentResult.anchor);
          _confirmed = ConstellationAnchorProjection(
            revision: parentResult.revision,
            anchors: _confirmed.anchors,
            pinnedPeers: _confirmed.pinnedPeers,
            pinnedRequests: _confirmed.pinnedRequests,
            supportPeers: _confirmed.supportPeers,
            supportEdges: _confirmed.supportEdges,
            serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
            serverFilteredBeaconCount: _confirmed.serverFilteredBeaconCount,
          );
          parentAdopted = true;
        }
        if (parentAdopted) {
          for (final companion in companions) {
            try {
              final result = await _anchorRepository.upsert(
                target: companion.target,
                position: companion.position,
              );
              if (writeAccount != _viewerAccountId ||
                  writeToken != _loadGeneration) {
                return const ConstellationAnchorWriteOutcome(
                  kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
                );
              }
              if (result.revision.compareTo(_confirmed.revision) >= 0) {
                _upsertConfirmedAnchor(result.anchor);
                _confirmed = ConstellationAnchorProjection(
                  revision: result.revision,
                  anchors: _confirmed.anchors,
                  pinnedPeers: _confirmed.pinnedPeers,
                  pinnedRequests: _confirmed.pinnedRequests,
                  supportPeers: _confirmed.supportPeers,
                  supportEdges: _confirmed.supportEdges,
                  serverFilteredBeaconIds: _confirmed.serverFilteredBeaconIds,
                  serverFilteredBeaconCount:
                      _confirmed.serverFilteredBeaconCount,
                );
              }
            } on Object catch (error, stackTrace) {
              mutationError ??= error;
              logger.warning(
                'Constellation companion anchor write failed',
                error,
                stackTrace,
              );
            }
          }
        }
      } on Object catch (error, stackTrace) {
        mutationError = error;
        logger.warning('Constellation anchor write failed', error, stackTrace);
        if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
          return const ConstellationAnchorWriteOutcome(
            kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          );
        }
      }

      var recoveryFailed = false;
      try {
        final projection = await _fetchAnchorsProjection(
          membershipFilters: membershipFilters,
        );
        if (writeAccount == _viewerAccountId && writeToken == _loadGeneration) {
          _applyIncomingProjection(
            projection,
            requestSeq: ++_anchorsRequestSeq,
          );
        }
      } on Object catch (error, stackTrace) {
        logger.warning(
          'Constellation anchor recovery read failed',
          error,
          stackTrace,
        );
        recoveryFailed = true;
      }

      if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
        return ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          projection: _confirmed,
        );
      }

      final parentOk = constellationAnchorAdoptedAt(
        anchors: _confirmed.anchors,
        target: parentTarget,
        intended: parentPosition,
      );
      final missedTitles = <String>[];
      for (final companion in companions) {
        if (!constellationAnchorAdoptedAt(
          anchors: _confirmed.anchors,
          target: companion.target,
          intended: companion.position,
        )) {
          missedTitles.add(
            companionTitles[companion.target.id] ?? companion.target.id,
          );
        }
      }

      if (parentOk && missedTitles.isEmpty) {
        _syncPending = recoveryFailed;
        return ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.succeeded,
          projection: _confirmed,
        );
      }

      _syncPending = true;
      final failureMessage = missedTitles.isEmpty
          ? (mutationError is ConstellationException
                ? (mutationError.message ??
                    'Could not save constellation placement.')
                : 'Could not save constellation placement.')
          : 'Could not move ${missedTitles.join(', ')}. '
              'Other placements were saved.';
      return ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.failed,
        projection: _confirmed,
        failureMessage: failureMessage,
      );
    } finally {
      if (identical(_pendingWrite, pending)) {
        _pendingWrite = null;
      }
    }
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
    if (generation != _loadGeneration || _pendingWrite != null) {
      return const ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
      );
    }
    final writeAccount = _viewerAccountId;
    final writeToken = _loadGeneration;
    _pendingWrite = pending;
    _writeCount++;
    var mutationSucceeded = false;
    Object? mutationError;
    try {
      try {
        final mutation = await action();
        if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
          return const ConstellationAnchorWriteOutcome(
            kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          );
        }
        mutationSucceeded = adoptMutation(mutation);
      } on Object catch (error, stackTrace) {
        mutationError = error;
        logger.warning('Constellation anchor write failed', error, stackTrace);
        if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
          return const ConstellationAnchorWriteOutcome(
            kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          );
        }
      }

      var recoveryFailed = false;
      try {
        final projection = await _fetchAnchorsProjection(
          membershipFilters: membershipFilters,
        );
        if (writeAccount == _viewerAccountId && writeToken == _loadGeneration) {
          _applyIncomingProjection(
            projection,
            requestSeq: ++_anchorsRequestSeq,
          );
        }
      } on Object catch (error, stackTrace) {
        logger.warning(
          'Constellation anchor recovery read failed',
          error,
          stackTrace,
        );
        recoveryFailed = true;
      }

      if (writeAccount != _viewerAccountId || writeToken != _loadGeneration) {
        return ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded,
          projection: _confirmed,
        );
      }
      if (mutationSucceeded) {
        _syncPending = recoveryFailed;
        return ConstellationAnchorWriteOutcome(
          kind: ConstellationAnchorWriteOutcomeKind.succeeded,
          projection: _confirmed,
        );
      }
      _syncPending = true;
      return ConstellationAnchorWriteOutcome(
        kind: ConstellationAnchorWriteOutcomeKind.failed,
        projection: _confirmed,
        failureMessage: mutationError is ConstellationException
            ? (mutationError.message ?? 'Could not save constellation placement.')
            : 'Could not save constellation placement.',
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
    if (generation != _loadGeneration) {
      return false;
    }
    return _applyIncomingProjection(
      incoming,
      requestSeq: ++_anchorsRequestSeq,
    );
  }

  bool _applyIncomingProjection(
    ConstellationAnchorProjection incoming, {
    int? requestSeq,
  }) {
    final comparison = incoming.revision.compareTo(_confirmed.revision);
    if (comparison < 0) {
      return false;
    }
    if (comparison == 0 &&
        requestSeq != null &&
        requestSeq < _lastAppliedRequestSeq) {
      return false;
    }
    _confirmed = incoming;
    if (requestSeq != null) {
      _lastAppliedRequestSeq = requestSeq;
    }
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
    unawaited(_refreshAnchorsOnce(membershipFilters: _membershipFilters));
  }

  Future<void> _refreshAnchorsOnce({
    ConstellationFieldMembershipFilters? membershipFilters,
  }) async {
    _queuedFilters = membershipFilters ?? _membershipFilters;
    _queuedAccountId = _viewerAccountId;
    _queuedLifecycleToken = _loadGeneration;
    _queuedRequestSeq = ++_anchorsRequestSeq;
    _anchorsRefreshQueued = true;
    final inFlight = _anchorsRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<void> future;
    future = _runAnchorsRefreshLoop().whenComplete(() {
      if (identical(_anchorsRefreshInFlight, future)) {
        _anchorsRefreshInFlight = null;
      }
      if (_anchorsRefreshQueued) {
        unawaited(_refreshAnchorsOnce(membershipFilters: _queuedFilters));
      }
    });
    _anchorsRefreshInFlight = future;
    return future;
  }

  Future<void> _runAnchorsRefreshLoop() async {
    do {
      _anchorsRefreshQueued = false;
      final filters = _queuedFilters;
      final account = _queuedAccountId;
      final token = _queuedLifecycleToken;
      final requestSeq = _queuedRequestSeq;
      try {
        final projection = await _fetchAnchorsProjection(
          membershipFilters: filters,
        );
        if (account != _viewerAccountId || token != _loadGeneration) {
          continue;
        }
        if (_applyIncomingProjection(projection, requestSeq: requestSeq)) {
          _refreshController.add(null);
        }
      } on Object catch (error, stackTrace) {
        logger.warning(
          'Constellation ANCHORS refresh failed',
          error,
          stackTrace,
        );
      }
    } while (_anchorsRefreshQueued);
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
