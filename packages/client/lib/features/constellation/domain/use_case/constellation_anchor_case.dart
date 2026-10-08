import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../entity/constellation_anchor_projection.dart';

@immutable
final class ConstellationAnchorsRefreshResult {
  const ConstellationAnchorsRefreshResult({
    required this.projection,
    required this.applied,
  });

  final ConstellationAnchorProjection projection;
  final bool applied;
}

/// Screen-scoped confirmed anchor cache and private realtime catch-up.
@Order(2)
@singleton
final class ConstellationAnchorCase extends UseCaseBase {
  ConstellationAnchorCase({
    required super.env,
    required super.logger,
  });

  String _viewerAccountId = '';
  int _loadGeneration = 0;
  bool _syncPending = false;

  ConstellationAnchorProjection _confirmed =
      ConstellationAnchorProjection.empty;

  int _anchorsRequestSeq = 0;
  int _lastAppliedRequestSeq = 0;

  ConstellationAnchorProjection get confirmedProjection => _confirmed;

  ConstellationAnchorRevision get projectionRevision => _confirmed.revision;

  bool get syncPending => _syncPending;

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
    _viewerAccountId = viewerAccountId;
    return _loadGeneration;
  }

  void deactivate({int? token}) {
    if (token != null && token != _loadGeneration) {
      return;
    }
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

  void _resetAccountOwnedState() {
    _confirmed = ConstellationAnchorProjection.empty;
    _syncPending = false;
    _lastAppliedRequestSeq = 0;
  }

  /// Seeds the confirmed cache from an accepted FULL snapshot.
  bool adoptConfirmedProjection(ConstellationAnchorProjection projection) {
    return _applyIncomingProjection(
      projection,
      requestSeq: ++_anchorsRequestSeq,
    );
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

  @disposeMethod
  Future<void> dispose() async {
    deactivate();
  }
}
