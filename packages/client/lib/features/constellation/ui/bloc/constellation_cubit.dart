import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:meta/meta.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_density.dart';
import '../../domain/constellation_filters.dart';
import '../../domain/constellation_layout.dart';
import '../../domain/constellation_consts.dart';
import '../../domain/constellation_path_resolution.dart';
import '../../domain/constellation_pin_position.dart';
import '../../domain/entity/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/use_case/constellation_anchor_case.dart';
import '../../domain/use_case/constellation_field_case.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/tentura_layout_algorithms.dart';
import 'constellation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'constellation_state.dart';

enum ConstellationEdgeKind {
  tier1Path,
  tier2Path,
  attachment,
  ringStub,
}

const kConstellationLayoutMaxHops = 3;

/// Server `HelpOfferCoordinationExceptionCode.offerKindChanged` wire code.
const kOfferKindChangedCoordinationCode = 1516;

enum ConstellationRequestPreflightOutcome {
  ready,
  authorizationDenied,
  requestUnavailable,
}

sealed class ConstellationRequestPreflight {
  const ConstellationRequestPreflight();

  const factory ConstellationRequestPreflight.ready({
    required ConstellationRequest request,
    required bool viewerHasActiveHelpOffer,
  }) = ConstellationRequestPreflightReady;

  const factory ConstellationRequestPreflight.authorizationDenied({
    required String message,
  }) = ConstellationRequestPreflightAuthorizationDenied;

  const factory ConstellationRequestPreflight.requestUnavailable({
    required String message,
  }) = ConstellationRequestPreflightUnavailable;
}

final class ConstellationRequestPreflightReady
    extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightReady({
    required this.request,
    required this.viewerHasActiveHelpOffer,
  });

  final ConstellationRequest request;
  final bool viewerHasActiveHelpOffer;
}

final class ConstellationRequestPreflightAuthorizationDenied
    extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightAuthorizationDenied({
    required this.message,
  });

  final String message;
}

final class ConstellationRequestPreflightUnavailable
    extends ConstellationRequestPreflight {
  const ConstellationRequestPreflightUnavailable({required this.message});

  final String message;
}

enum ConstellationOfferSubmitOutcome {
  success,
  offerKindChanged,
  validationFailed,
}

/// Per-node absence classification (architecture §5.2 — presentation only).
enum ConstellationNodeAbsence {
  none,
  filterHidden,
  spaceCollapsed,
  ring,
  capDisplaced,
  ringBudgetOmitted,
}

final class ConstellationCubit extends Cubit<ConstellationState> {
  ConstellationCubit({
    required ConstellationFieldCase case_,
    required Profile viewer,
    ConstellationAnchorCase? anchorCase,
    ForwardRepository? forwardRepository,
    bool loadOnCreate = true,
  }) : _case = case_,
       _anchorCase = anchorCase,
       _viewer = viewer,
       _forwardRepositoryOverride = forwardRepository,
       super(const ConstellationState()) {
    _anchorLifecycleToken = _anchorCase?.activate(viewerAccountId: viewer.id);
    _anchorRefreshSub = _anchorCase?.refreshSignals.listen(
      (_) => unawaited(_onAnchorRefreshHint()),
      cancelOnError: false,
    );
    if (loadOnCreate) {
      unawaited(load());
    }
  }

  final ConstellationFieldCase _case;
  final ConstellationAnchorCase? _anchorCase;
  final Profile _viewer;
  final ForwardRepository? _forwardRepositoryOverride;

  StreamSubscription<void>? _anchorRefreshSub;
  int? _anchorLifecycleToken;
  int _layoutReconciliationCount = 0;
  bool _suppressLateGestureEnd = false;
  String? _draggingNodeId;
  ConstellationLayoutPriorHints? _layoutPriorHints;

  ForwardRepository get _forwardRepository =>
      _forwardRepositoryOverride ?? GetIt.I<ForwardRepository>();

  final graphController = GraphController<NodeDetails, EdgeDetails<NodeDetails>>(
    nodeIdOf: (node) => node.id,
    edgeIdOf: (edge) => 'd:${edge.source.id}->${edge.destination.id}',
  );

  final Map<String, ConstellationEdgeKind> edgeKinds = {};

  String layoutEgoId = '';
  Map<String, List<String>> layoutVisibleRequestsByAuthor = const {};
  Set<String> layoutEgoOwnRequestIds = const {};
  Set<String> droppedHolderIds = const {};
  Set<String> displayedRequestIds = const {};
  Map<String, int> overflowHiddenCountByAuthor = const {};
  final Set<String> expandedSatelliteAuthorIds = {};

  Size _labelBudgetViewport = const Size(1200, 900);
  double _labelBudgetTextScale = 1.0;

  @visibleForTesting
  int get layoutReconciliationCount => _layoutReconciliationCount;

  @visibleForTesting
  int get writeCount => _anchorCase?.writeCount ?? 0;

  bool get placementActionsEnabled =>
      state.placementActionsEnabled && !(_anchorCase?.hasPendingWrite ?? false);

  ConstellationLayoutAlgorithm get mapLayoutAlgorithm {
    final overlay =
        state.composition?.anchorOverlay ?? ConstellationAnchorOverlay.empty;
    return ConstellationLayoutAlgorithm(
      egoId: layoutEgoId.isEmpty ? _viewer.id : layoutEgoId,
      paths:
          state.paths ??
          resolveConstellationPaths(
            egoId: _viewer.id,
            visiblePeerIds: const {},
            holderIds: {_viewer.id},
            edges: const [],
          ),
      keptPeerIds: state.keptPeerIds,
      maxHops: kConstellationLayoutMaxHops,
      visibleRequestsByAuthor: layoutVisibleRequestsByAuthor,
      egoOwnRequestIds: layoutEgoOwnRequestIds,
      pinnedPersonIds: {
        for (final peer in overlay.pinnedPeers) peer.id,
        for (final anchor in overlay.anchors)
          if (anchor.target.kind == ConstellationAnchorTargetKind.person)
            anchor.target.id,
      },
      pinnedRequestIds: {
        for (final request in overlay.pinnedRequests) request.id,
        for (final anchor in overlay.anchors)
          if (anchor.target.kind == ConstellationAnchorTargetKind.beacon)
            anchor.target.id,
      },
      supportPersonIds: {
        for (final peer in overlay.supportPeers) peer.id,
      },
      anchorByNodeId: {
        for (final entry in constellationAnchorsByNodeId(
          overlay.anchors,
        ).entries)
          entry.key: entry.value.position,
      },
    );
  }

  @override
  Future<void> close() async {
    await _anchorRefreshSub?.cancel();
    _anchorCase?.deactivate(token: _anchorLifecycleToken);
    return super.close();
  }

  Future<void> load() async {
    if (isClosed) {
      return;
    }
    final generation = state.loadGeneration + 1;
    emit(
      state.copyWith(
        status: StateIsLoading(),
        loadError: null,
        loadGeneration: generation,
      ),
    );
    _anchorCase?.syncMembershipFilters(state.membershipFilters);
    try {
      final resolved = await _case.load(
        viewerId: _viewer.id,
        membershipFilters: state.membershipFilters,
        localFilters: state.filters,
        labelBudget: constellationLabelBudget(
          viewport: _labelBudgetViewport,
          textScaleFactor: _labelBudgetTextScale,
        ),
      );
      if (isClosed || generation != state.loadGeneration) {
        return;
      }
      final adopted =
          _anchorCase?.adoptConfirmedProjection(
            resolved.field.resolvedAnchorProjection,
          ) ??
          true;
      final confirmedProjection =
          _anchorCase?.confirmedProjection ??
          resolved.field.resolvedAnchorProjection;
      final loadedField = adopted
          ? resolved.field
          : resolved.field.copyWith(anchorProjection: confirmedProjection);
      final composition = composeConstellationPresentation(
        viewerId: _viewer.id,
        field: loadedField,
        localFilters: state.filters,
        asOfUtc: loadedField.loadedAt,
        labelBudget: constellationLabelBudget(
          viewport: _labelBudgetViewport,
          textScaleFactor: _labelBudgetTextScale,
        ),
        expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
      );
      emit(
        state.copyWith(
          status: StateIsSuccess(),
          loadedAt: loadedField.loadedAt,
          field: loadedField,
          composition: composition,
          paths: composition.paths,
          keptPeerIds: composition.keptPeerIds,
          capped: composition.renderBudgetCapped,
          loadError: null,
          syncPending: _anchorCase?.syncPending ?? false,
          placementActionsEnabled: true,
        ),
      );
      droppedHolderIds = composition.droppedHolderIds;
      _reconcileSelection(composition);
      _reconcileLayout();
    } on Object catch (error) {
      if (isClosed || generation != state.loadGeneration) {
        return;
      }
      emit(
        state.copyWith(
          status: StateIsSuccess(),
          loadError: error,
        ),
      );
    }
  }

  String get viewerId => _viewer.id;

  Profile get viewer => _viewer;

  Future<void> onAccountChanged() async {
    if (isClosed) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    final generation =
        _anchorCase?.onAccountChanged() ?? state.loadGeneration + 1;
    _anchorLifecycleToken =
        _anchorCase?.activate(viewerAccountId: _viewer.id) ?? generation;
    emit(
      state.copyWith(
        loadGeneration: generation,
        field: null,
        composition: null,
        paths: null,
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: null,
        deferredRefreshTarget: null,
        placementFailureMessage: null,
        syncPending: false,
      ),
    );
  }

  void beginDragExisting({
    required ConstellationAnchorTarget target,
  }) {
    if (isClosed || !placementActionsEnabled) {
      return;
    }
    _suppressLateGestureEnd = false;
    _draggingNodeId = target.graphNodeId;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.draggingExisting,
        activePlacementTarget: target,
        placementFailureMessage: null,
        placementActionsEnabled: false,
      ),
    );
  }

  void beginDragNew({required ConstellationAnchorTarget target}) {
    if (isClosed || !placementActionsEnabled) {
      return;
    }
    _suppressLateGestureEnd = false;
    _draggingNodeId = target.graphNodeId;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.draggingNew,
        activePlacementTarget: target,
        placementFailureMessage: null,
        placementActionsEnabled: false,
      ),
    );
  }

  void updateDragPresentation({
    required String nodeId,
    required Offset sceneCentre,
  }) {
    if (isClosed || _draggingNodeId != nodeId) {
      return;
    }
    final node = graphController.nodes
        .where((candidate) => candidate.id == nodeId)
        .cast<NodeDetails?>()
        .whereType<NodeDetails>()
        .firstOrNull;
    if (node == null) {
      return;
    }
    graphController.setNodePresentationPosition(node, sceneCentre);
  }

  Future<void> onExistingNodeDrop({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) async {
    if (isClosed || _suppressLateGestureEnd) {
      return;
    }
    final position = constellationPointToV1Anchor(
      (x: sceneCentre.dx, y: sceneCentre.dy),
    );
    _draggingNodeId = null;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: target,
        placementActionsEnabled: false,
      ),
    );
    await _submitUpsert(target: target, position: position);
  }

  Future<void> onNewNodeDrop({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) async {
    if (isClosed || _suppressLateGestureEnd) {
      return;
    }
    updateDragPresentation(
      nodeId: target.graphNodeId,
      sceneCentre: sceneCentre,
    );
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.provisionalNew,
        activePlacementTarget: target,
        placementActionsEnabled: true,
      ),
    );
  }

  Future<void> confirmProvisionalPin({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) async {
    if (isClosed ||
        state.placementPhase != ConstellationPlacementPhase.provisionalNew) {
      return;
    }
    final position = constellationPointToV1Anchor(
      (x: sceneCentre.dx, y: sceneCentre.dy),
    );
    _draggingNodeId = null;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: target,
        placementActionsEnabled: false,
      ),
    );
    await _submitUpsert(target: target, position: position);
  }

  Future<void> pinFromText({required ConstellationAnchorTarget target}) async {
    if (isClosed || !placementActionsEnabled) {
      return;
    }
    final composition = state.composition;
    if (composition == null) {
      return;
    }
    final layoutInput = layoutInputFromComposition(
      viewerId: _viewer.id,
      composition: composition,
      labelPlan: composition.labelPlan,
      nodeSizes: const {},
      spacing: 16,
      priorHints: _layoutPriorHints,
    );
    final position = computeConstellationPinPosition(
      target: target,
      layoutInput: layoutInput,
    );
    if (position == null) {
      return;
    }
    emit(
      state.copyWith(
        activePlacementTarget: target,
        placementActionsEnabled: false,
      ),
    );
    await _submitUpsert(target: target, position: position);
  }

  Future<void> unpinAnchor({required ConstellationAnchorTarget target}) async {
    if (isClosed || !placementActionsEnabled || _anchorCase == null) {
      return;
    }
    emit(state.copyWith(placementActionsEnabled: false));
    final outcome = await _anchorCase!.deleteAnchor(
      target: target,
      generation: _anchorCase!.lifecycleToken,
      membershipFilters: state.membershipFilters,
    );
    if (isClosed) {
      return;
    }
    await _applyWriteOutcome(outcome);
  }

  void cancelPlacement({bool suppressLateGestureEnd = true}) {
    if (isClosed) {
      return;
    }
    _cancelUnsentPlacement(
      write: false,
      suppressLateGestureEnd: suppressLateGestureEnd,
    );
  }

  void onRouteLeave() => cancelPlacement();

  void onPointerCancelDuringDrag() {
    if (isClosed) {
      return;
    }
    _cancelUnsentPlacement(write: false);
  }

  Future<void> _submitUpsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  }) async {
    if (_anchorCase == null) {
      return;
    }
    final outcome = await _anchorCase!.upsert(
      target: target,
      position: position,
      generation: _anchorCase!.lifecycleToken,
      membershipFilters: state.membershipFilters,
    );
    if (isClosed) {
      return;
    }
    await _applyWriteOutcome(outcome);
  }

  Future<void> _applyWriteOutcome(
    ConstellationAnchorWriteOutcome outcome,
  ) async {
    switch (outcome.kind) {
      case ConstellationAnchorWriteOutcomeKind.succeeded:
        await _mergeConfirmedProjection(outcome.projection);
        emit(
          state.copyWith(
            placementPhase: ConstellationPlacementPhase.idle,
            activePlacementTarget: null,
            deferredRefreshTarget: null,
            placementFailureMessage: null,
            syncPending: _anchorCase?.syncPending ?? false,
            placementActionsEnabled: true,
          ),
        );
        _reconcileLayout();
      case ConstellationAnchorWriteOutcomeKind.failed:
        await _mergeConfirmedProjection(outcome.projection);
        emit(
          state.copyWith(
            placementPhase: ConstellationPlacementPhase.idle,
            activePlacementTarget: null,
            deferredRefreshTarget: null,
            placementFailureMessage: outcome.failureMessage,
            syncPending: _anchorCase?.syncPending ?? false,
            placementActionsEnabled: true,
          ),
        );
        _reconcileLayout();
      case ConstellationAnchorWriteOutcomeKind.staleResponseDiscarded:
        emit(
          state.copyWith(
            placementPhase: ConstellationPlacementPhase.idle,
            activePlacementTarget: null,
            deferredRefreshTarget: null,
            placementActionsEnabled: true,
          ),
        );
    }
  }

  bool _shouldDeferPlacementRefresh() {
    final target = state.activePlacementTarget;
    if (target == null) {
      return false;
    }
    return state.hasPendingPlacementWrite ||
        (_anchorCase?.hasPendingWrite ?? false);
  }

  Future<void> _onAnchorRefreshHint() async {
    if (isClosed || _anchorCase == null) {
      return;
    }
    final deferPresentation = _shouldDeferPlacementRefresh();
    final deferTarget = deferPresentation ? state.activePlacementTarget : null;
    await _mergeConfirmedProjection(
      _anchorCase!.confirmedProjection,
      deferTarget: deferTarget,
    );
    if (isClosed) {
      return;
    }
    if (deferPresentation) {
      emit(
        state.copyWith(
          deferredRefreshTarget: deferTarget,
          syncPending: _anchorCase!.syncPending,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        deferredRefreshTarget: null,
        syncPending: _anchorCase!.syncPending,
      ),
    );
    _reconcileLayout();
  }

  ConstellationAnchorProjection _presentationProjection(
    ConstellationAnchorProjection incoming, {
    ConstellationAnchorTarget? deferTarget,
  }) {
    if (deferTarget == null) {
      return incoming;
    }
    final baseline = state.field?.resolvedAnchorProjection;
    if (baseline == null) {
      return incoming;
    }
    final baselineAnchor = baseline.anchors
        .where((anchor) => anchor.target == deferTarget)
        .firstOrNull;
    if (baselineAnchor == null) {
      return incoming;
    }
    final anchors = [
      for (final anchor in incoming.anchors)
        if (anchor.target == deferTarget) baselineAnchor else anchor,
    ];
    return ConstellationAnchorProjection(
      revision: incoming.revision,
      anchors: anchors,
      pinnedPeers: incoming.pinnedPeers,
      pinnedRequests: incoming.pinnedRequests,
      supportPeers: incoming.supportPeers,
      supportEdges: incoming.supportEdges,
      serverFilteredBeaconIds: incoming.serverFilteredBeaconIds,
      serverFilteredBeaconCount: incoming.serverFilteredBeaconCount,
    );
  }

  Future<void> _mergeConfirmedProjection(
    ConstellationAnchorProjection? projection, {
    ConstellationAnchorTarget? deferTarget,
  }) async {
    final confirmed = projection ?? _anchorCase?.confirmedProjection;
    final field = state.field;
    if (confirmed == null || field == null) {
      return;
    }
    final presentation = _presentationProjection(
      confirmed,
      deferTarget: deferTarget,
    );
    final mergedField = field.copyWith(anchorProjection: presentation);
    final composition = composeConstellationPresentation(
      viewerId: _viewer.id,
      field: mergedField,
      localFilters: state.filters,
      asOfUtc: state.loadedAt ?? field.loadedAt,
      labelBudget: constellationLabelBudget(
        viewport: _labelBudgetViewport,
        textScaleFactor: _labelBudgetTextScale,
      ),
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
    );
    emit(
      state.copyWith(
        field: mergedField,
        composition: composition,
        paths: composition.paths,
        keptPeerIds: composition.keptPeerIds,
        capped: composition.renderBudgetCapped,
      ),
    );
    droppedHolderIds = composition.droppedHolderIds;
    _reconcileSelection(composition);
  }

  void _reconcileSelection(ConstellationComposedPresentation composition) {
    final selectedPersonId = state.selectedPersonId;
    final selectedRequestId = state.selectedRequestId;
    final clearPerson =
        selectedPersonId != null &&
        !composition.eligiblePersonIds.contains(selectedPersonId);
    final clearRequest =
        selectedRequestId != null &&
        !composition.eligibleRequestIds.contains(selectedRequestId);
    if (!clearPerson && !clearRequest) {
      return;
    }
    emit(
      state.copyWith(
        selectedPersonId: clearPerson ? null : selectedPersonId,
        selectedRequestId: clearRequest ? null : selectedRequestId,
      ),
    );
  }

  void _cancelUnsentPlacement({
    required bool write,
    bool suppressLateGestureEnd = true,
  }) {
    if (suppressLateGestureEnd) {
      _suppressLateGestureEnd = true;
    }
    final target = state.activePlacementTarget;
    if (target != null) {
      _clearDragPresentation(target.graphNodeId);
    }
    _draggingNodeId = null;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: null,
        deferredRefreshTarget: null,
        placementActionsEnabled: true,
        placementFailureMessage: null,
      ),
    );
    if (!write) {
      _reconcileLayout();
    }
  }

  void _clearDragPresentation(String nodeId) {
    final node = graphController.nodes
        .where((candidate) => candidate.id == nodeId)
        .cast<NodeDetails?>()
        .whereType<NodeDetails>()
        .firstOrNull;
    if (node != null) {
      graphController.clearPresentationPosition(node);
    }
    _draggingNodeId = null;
  }

  void selectRequest(String? requestId) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        selectedRequestId: requestId,
        selectedPersonId: requestId != null ? null : state.selectedPersonId,
      ),
    );
  }

  void setViewMode(ConstellationViewMode viewMode) {
    if (isClosed || state.viewMode == viewMode) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(viewMode: viewMode));
  }

  void updateLabelBudgetContext({
    required Size viewport,
    required double textScaleFactor,
  }) {
    _labelBudgetViewport = viewport;
    _labelBudgetTextScale = textScaleFactor;
    if (!state.hasPendingPlacementWrite) {
      _reconcileLayout(deferAutomaticReflow: true);
    }
  }

  bool get hasActiveFilters =>
      state.filterCapabilitySlugs.isNotEmpty ||
      state.filterLocation != LocationFilter.any ||
      state.filterTiming is! TimingFilterAny ||
      !state.filterIncludeUnspecified ||
      state.membershipFilters.showClosed ||
      state.membershipFilters.participatedOnly;

  bool get canClearFilters => hasActiveFilters;

  int get hiddenPinnedBeaconCount {
    final composition = state.composition;
    final projection = state.confirmedProjection;
    if (composition == null || projection == null) {
      return 0;
    }
    return {
      ...projection.serverFilteredBeaconIds,
      ...composition.locallyFilteredPinnedBeaconIds,
    }.length;
  }

  bool isAnchored(ConstellationAnchorTarget target) {
    final anchors =
        state.composition?.anchorOverlay.anchors ??
        state.confirmedProjection?.anchors ??
        const <ConstellationAnchor>[];
    return anchors.any((anchor) => anchor.target == target);
  }

  bool canPinTarget(ConstellationAnchorTarget target) {
    if (isAnchored(target)) {
      return true;
    }
    final composition = state.composition;
    if (composition == null) {
      return false;
    }
    final layoutInput = layoutInputFromComposition(
      viewerId: _viewer.id,
      composition: composition,
      labelPlan: composition.labelPlan,
      nodeSizes: const {},
      spacing: 16,
      priorHints: _layoutPriorHints,
    );
    return computeConstellationPinPosition(
          target: target,
          layoutInput: layoutInput,
        ) !=
        null;
  }

  ConstellationAnchorTarget? anchorTargetForNode(NodeDetails node) =>
      switch (node) {
        FieldPersonNode(:final person) =>
          person.id == viewerId
              ? null
              : ConstellationAnchorTarget.person(person.id),
        FieldRequestNode(:final request) => ConstellationAnchorTarget.beacon(
          request.id,
        ),
        _ => null,
      };

  bool canDragNode(NodeDetails node) {
    if (anchorTargetForNode(node) == null) {
      return false;
    }
    if (state.placementPhase == ConstellationPlacementPhase.provisionalNew) {
      return false;
    }
    return placementActionsEnabled ||
        state.placementPhase == ConstellationPlacementPhase.draggingExisting ||
        state.placementPhase == ConstellationPlacementPhase.draggingNew;
  }

  List<NodeDetails> orderedNodesForPaint() {
    final nodes = graphController.nodes.whereType<NodeDetails>().toList();
    if (nodes.isEmpty) {
      return nodes;
    }
    final anchors = [
      ...?state.composition?.anchorOverlay.anchors,
      ...?state.confirmedProjection?.anchors,
    ];
    final anchorByNodeId = constellationAnchorsByNodeId(anchors);
    final anchored = <NodeDetails>[];
    final unanchored = <NodeDetails>[];
    for (final node in nodes) {
      if (anchorByNodeId.containsKey(node.id)) {
        anchored.add(node);
      } else {
        unanchored.add(node);
      }
    }
    anchored.sort((a, b) {
      final anchorA = anchorByNodeId[a.id]!;
      final anchorB = anchorByNodeId[b.id]!;
      return ConstellationAnchor.comparePaintOrder(anchorA, anchorB);
    });
    final ordered = [...unanchored, ...anchored];
    final active = state.activePlacementTarget;
    if (active != null &&
        (state.placementPhase == ConstellationPlacementPhase.draggingExisting ||
            state.placementPhase == ConstellationPlacementPhase.draggingNew ||
            state.placementPhase ==
                ConstellationPlacementPhase.provisionalNew)) {
      final activeNode = ordered
          .where((node) => node.id == active.graphNodeId)
          .firstOrNull;
      if (activeNode != null) {
        ordered
          ..remove(activeNode)
          ..add(activeNode);
      }
    }
    return ordered;
  }

  bool get isFilteredResultEmpty {
    final field = state.field;
    if (field == null) {
      return false;
    }
    return hasActiveFilters && _filteredRequestIds(field).isEmpty;
  }

  bool get peersCapped => state.field?.peersCapped ?? false;

  bool get requestsCapped => state.field?.requestsCapped ?? false;

  bool get renderBudgetCapped => state.capped;

  void setFilterCapabilitySlugs(Set<String> slugs) {
    if (isClosed) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(filterCapabilitySlugs: slugs));
    _recomposeAndLayout();
  }

  void setFilterLocation(LocationFilter location) {
    if (isClosed || state.filterLocation == location) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(filterLocation: location));
    _recomposeAndLayout();
  }

  void setFilterTiming(TimingFilter timing) {
    if (isClosed || state.filterTiming == timing) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(filterTiming: timing));
    _recomposeAndLayout();
  }

  void setFilterIncludeUnspecified(bool include) {
    if (isClosed || state.filterIncludeUnspecified == include) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(filterIncludeUnspecified: include));
    _recomposeAndLayout();
  }

  Future<void> setShowClosed(bool showClosed) async {
    if (isClosed || state.membershipFilters.showClosed == showClosed) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    final filters = ConstellationFieldMembershipFilters(
      showClosed: showClosed,
      participatedOnly: state.membershipFilters.participatedOnly,
    );
    emit(state.copyWith(membershipFilters: filters));
    _anchorCase?.syncMembershipFilters(filters);
    await load();
  }

  Future<void> setParticipatedOnly(bool participatedOnly) async {
    if (isClosed ||
        state.membershipFilters.participatedOnly == participatedOnly) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    final filters = ConstellationFieldMembershipFilters(
      showClosed: state.membershipFilters.showClosed,
      participatedOnly: participatedOnly,
    );
    emit(state.copyWith(membershipFilters: filters));
    _anchorCase?.syncMembershipFilters(filters);
    await load();
  }

  Future<void> clearFilters() async {
    if (isClosed || !canClearFilters) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    final hadMembershipFilters =
        state.membershipFilters.showClosed ||
        state.membershipFilters.participatedOnly;
    const defaultMembership = ConstellationFieldMembershipFilters.defaults;
    emit(
      state.copyWith(
        filterCapabilitySlugs: const {},
        filterLocation: LocationFilter.any,
        filterTiming: const TimingFilterAny(),
        filterIncludeUnspecified: true,
        membershipFilters: defaultMembership,
      ),
    );
    _anchorCase?.syncMembershipFilters(defaultMembership);
    if (hadMembershipFilters) {
      await load();
    } else {
      _recomposeAndLayout();
    }
  }

  void toggleSatelliteOverflow(String authorId) {
    if (isClosed) {
      return;
    }
    if (expandedSatelliteAuthorIds.contains(authorId)) {
      expandedSatelliteAuthorIds.remove(authorId);
    } else {
      expandedSatelliteAuthorIds.add(authorId);
    }
    if (!state.hasPendingPlacementWrite) {
      _recomposeAndLayout();
    }
  }

  bool isSatelliteOverflowExpanded(String authorId) =>
      expandedSatelliteAuthorIds.contains(authorId);

  Set<String> availableCapabilitySlugs() {
    final field = state.field;
    if (field == null) {
      return const {};
    }
    final slugs = <String>{};
    for (final request in field.requests) {
      slugs.addAll(request.needs);
      final primary = request.primaryNeedSlug?.trim();
      if (primary != null && primary.isNotEmpty) {
        slugs.add(primary);
      }
    }
    return slugs;
  }

  ConstellationNodeAbsence absenceForPerson(String personId) {
    if (personId == _viewer.id) {
      return ConstellationNodeAbsence.none;
    }
    final paths = state.paths;
    if (paths == null) {
      return ConstellationNodeAbsence.none;
    }
    if (droppedHolderIds.contains(personId)) {
      return ConstellationNodeAbsence.capDisplaced;
    }
    if (paths.ring.contains(personId)) {
      if (!state.keptPeerIds.contains(personId)) {
        return ConstellationNodeAbsence.ringBudgetOmitted;
      }
      return ConstellationNodeAbsence.ring;
    }
    return ConstellationNodeAbsence.none;
  }

  ConstellationNodeAbsence absenceForRequest(String requestId) {
    final field = state.field;
    if (field == null) {
      return ConstellationNodeAbsence.none;
    }
    final filtered = _filteredRequestIds(field);
    if (!filtered.contains(requestId)) {
      return ConstellationNodeAbsence.filterHidden;
    }
    if (displayedRequestIds.contains(requestId)) {
      return ConstellationNodeAbsence.none;
    }
    return ConstellationNodeAbsence.spaceCollapsed;
  }

  String ringSemanticsKeyForPerson(String personId) {
    if (peersCapped && (state.paths?.ring.contains(personId) ?? false)) {
      return 'constellationAbsencePathNotShown';
    }
    return 'constellationAbsenceRing';
  }

  /// Refreshes a single request's status/offer/forward flags before an
  /// action (Offer Help / Forward) commits. This MUST stay on a
  /// content-wall-gated data source (`_case.load`, the same
  /// [ConstellationFieldCase] the initial field snapshot came from) rather
  /// than an involvement-gated one (e.g. `fetchBeaconInvolvement`) —
  /// discovery-only Constellation viewers per D11 have content-read access
  /// but never involvement/discussion-admission access, so an
  /// involvement-gated preflight would always deny the primary Constellation
  /// action flow. Only the one matching request is merged into state
  /// ([_replaceRequestInField]); this must not update `state.loadedAt` or
  /// otherwise claim the whole field was refreshed.
  Future<ConstellationRequestPreflight> preflightRequestAction(
    String beaconId,
  ) async {
    try {
      final resolved = await _case.load(viewerId: _viewer.id);
      ConstellationRequest? refreshed;
      for (final request in resolved.field.requests) {
        if (request.id == beaconId) {
          refreshed = request;
          break;
        }
      }
      if (refreshed == null) {
        return const ConstellationRequestPreflight.requestUnavailable(
          message: 'This request is no longer in the field snapshot.',
        );
      }
      final status = BeaconStatus.fromSmallint(refreshed.status);
      if (!status.isOpenFamily) {
        return ConstellationRequestPreflight.authorizationDenied(
          message: _authorizationDeniedMessage(status),
        );
      }
      _replaceRequestInField(refreshed);
      return ConstellationRequestPreflight.ready(
        request: refreshed,
        viewerHasActiveHelpOffer: refreshed.viewerHasActiveHelpOffer,
      );
    } on Object catch (error) {
      if (_isAuthorizationFailure(error)) {
        return const ConstellationRequestPreflight.authorizationDenied(
          message: 'You can no longer act on this request.',
        );
      }
      return ConstellationRequestPreflight.requestUnavailable(
        message: error.toString(),
      );
    }
  }

  Future<ConstellationOfferSubmitOutcome> submitValidatedOfferHelp({
    required String beaconId,
    required int expectedOfferKind,
    required String message,
    List<String>? helpTypes,
  }) async {
    try {
      final ok = await _forwardRepository.offerHelp(
        beaconId: beaconId,
        message: message,
        helpTypes: helpTypes,
        expectedOfferKind: expectedOfferKind,
      );
      if (!ok) {
        return ConstellationOfferSubmitOutcome.validationFailed;
      }
      await preflightRequestAction(beaconId);
      return ConstellationOfferSubmitOutcome.success;
    } on Object catch (error) {
      if (_isOfferKindChanged(error)) {
        return ConstellationOfferSubmitOutcome.offerKindChanged;
      }
      return ConstellationOfferSubmitOutcome.validationFailed;
    }
  }

  int expectedOfferKindForRequest(ConstellationRequest request) {
    return BeaconStatus.fromSmallint(request.status) == BeaconStatus.enoughHelp
        ? 1
        : 0;
  }

  bool coverageRequiresExplicitBackupChoice({
    required ConstellationRequest snapshotRequest,
    required ConstellationRequest freshRequest,
  }) {
    final snapshotOpen =
        BeaconStatus.fromSmallint(snapshotRequest.status) !=
        BeaconStatus.enoughHelp;
    final freshCovered =
        BeaconStatus.fromSmallint(freshRequest.status) ==
        BeaconStatus.enoughHelp;
    return snapshotOpen && freshCovered;
  }

  void selectPerson(String? personId) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        selectedPersonId: personId,
        selectedRequestId: personId != null ? null : state.selectedRequestId,
      ),
    );
  }

  void togglePersonRequestsExpanded(String personId) {
    if (isClosed) {
      return;
    }
    final expanded = Set<String>.from(state.expandedPersonIds);
    if (expanded.contains(personId)) {
      expanded.remove(personId);
    } else {
      expanded.add(personId);
    }
    emit(state.copyWith(expandedPersonIds: expanded));
  }

  ConstellationRequest? requestById(String requestId) {
    final field = state.field;
    if (field == null) {
      return null;
    }
    for (final request in field.requests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  Profile? profileForPersonId(String personId) {
    if (personId == _viewer.id) {
      return _viewer;
    }
    final field = state.field;
    if (field == null) {
      return null;
    }
    for (final peer in field.peers) {
      if (peer.id == personId) {
        return _profileFromPeer(peer);
      }
    }
    return null;
  }

  List<ConstellationRequest> discoverableRequestsForPerson(String personId) {
    final field = state.field;
    if (field == null) {
      return const [];
    }
    final filteredRequestIds = _filteredRequestIds(field);
    return [
      for (final request in field.requests)
        if (request.authorId == personId &&
            filteredRequestIds.contains(request.id))
          request,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  Set<String> _filteredRequestIds(ConstellationField field) {
    final asOf = state.loadedAt ?? field.loadedAt;
    return filterRequestIds(
      requests: field.requests.map(
        (request) => (
          id: request.id,
          needs: request.needs.toSet(),
          primaryNeedSlug: request.primaryNeedSlug,
          startAt: request.startAt,
          endAt: request.endAt,
          addressLabel: request.addressLabel,
          hasCoordinates: request.hasCoordinates,
        ),
      ),
      filters: state.filters,
      asOfUtc: asOf.toUtc(),
    );
  }

  Map<String, List<String>> _allRequestsByAuthor(ConstellationField field) {
    final byAuthor = <String, List<String>>{};
    for (final request in field.requests) {
      byAuthor.putIfAbsent(request.authorId, () => <String>[]).add(request.id);
    }
    for (final entry in byAuthor.entries) {
      entry.value.sort();
    }
    return byAuthor;
  }

  ({
    Set<String> drawnRequestIds,
    Map<String, List<String>> layoutByAuthor,
    Set<String> egoOwnRequestIds,
    Map<String, int> overflowByAuthor,
  })
  _displayPlan(ConstellationField field) {
    final allByAuthor = _allRequestsByAuthor(field);
    final filteredIds = _filteredRequestIds(field);

    final filteredByAuthor = <String, List<String>>{};
    for (final entry in allByAuthor.entries) {
      final ids = [
        for (final id in entry.value)
          if (filteredIds.contains(id)) id,
      ];
      if (ids.isNotEmpty) {
        filteredByAuthor[entry.key] = ids;
      }
    }

    final budget = constellationLabelBudget(
      viewport: _labelBudgetViewport,
      textScaleFactor: _labelBudgetTextScale,
    );
    final allocated = allocateVisibleRequests(
      requestIdsByAuthor: filteredByAuthor,
      budget: budget,
    );

    final drawn = <String>{};
    final overflow = <String, int>{};

    for (final entry in filteredByAuthor.entries) {
      final authorId = entry.key;
      final allIds = entry.value;
      final visibleIds = List<String>.from(allocated[authorId] ?? const []);
      if (expandedSatelliteAuthorIds.contains(authorId)) {
        visibleIds
          ..clear()
          ..addAll(allIds);
      }
      final hidden = allIds.length - visibleIds.length;
      if (hidden > 0) {
        overflow[authorId] = hidden;
      }
      drawn.addAll(visibleIds);
    }

    return (
      drawnRequestIds: drawn,
      layoutByAuthor: allByAuthor,
      egoOwnRequestIds: {
        for (final id in allByAuthor[_viewer.id] ?? const <String>[]) id,
      },
      overflowByAuthor: overflow,
    );
  }

  void _recomposeAndLayout() {
    final field = state.field;
    if (field == null) {
      return;
    }
    final composition = composeConstellationPresentation(
      viewerId: _viewer.id,
      field: field,
      localFilters: state.filters,
      asOfUtc: state.loadedAt ?? field.loadedAt,
      labelBudget: constellationLabelBudget(
        viewport: _labelBudgetViewport,
        textScaleFactor: _labelBudgetTextScale,
      ),
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
    );
    emit(
      state.copyWith(
        composition: composition,
        paths: composition.paths,
        keptPeerIds: composition.keptPeerIds,
        capped: composition.renderBudgetCapped,
      ),
    );
    droppedHolderIds = composition.droppedHolderIds;
    _reconcileSelection(composition);
    _reconcileLayout(
      deferAutomaticReflow:
          state.hasPendingPlacementWrite ||
          (_anchorCase?.hasPendingWrite ?? false),
    );
  }

  void _reconcileLayout({bool deferAutomaticReflow = false}) {
    if (deferAutomaticReflow &&
        (state.hasPendingPlacementWrite ||
            (_anchorCase?.hasPendingWrite ?? false) ||
            _draggingNodeId != null)) {
      return;
    }
    _layoutReconciliationCount++;
    _rebuildGraph();
  }

  void _rebuildGraph() {
    if (_draggingNodeId != null &&
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    final field = state.field;
    final paths = state.paths;
    final composition = state.composition;
    if (field == null || paths == null) {
      graphController.clear();
      edgeKinds.clear();
      overflowHiddenCountByAuthor = const {};
      return;
    }

    final peersById = {
      for (final peer in field.peers) peer.id: peer,
    };
    final overlay = composition?.anchorOverlay;
    if (overlay != null) {
      for (final peer in overlay.pinnedPeers) {
        peersById.putIfAbsent(peer.id, () => peer);
      }
      for (final peer in overlay.supportPeers) {
        peersById.putIfAbsent(peer.id, () => peer);
      }
    }
    final ConstellationLabelDisplayPlan plan;
    if (composition != null) {
      plan = composition.labelPlan;
    } else {
      final legacy = _displayPlan(field);
      plan = ConstellationLabelDisplayPlan(
        drawnRequestIds: legacy.drawnRequestIds,
        layoutRequestsByAuthor: legacy.layoutByAuthor,
        egoOwnRequestIds: legacy.egoOwnRequestIds,
        overflowHiddenCountByAuthor: legacy.overflowByAuthor,
        pinnedRequestIds: const {},
      );
    }
    final drawnRequestIds = plan.drawnRequestIds;

    final requestsById = {
      for (final request in field.requests) request.id: request,
    };
    if (overlay != null) {
      for (final request in overlay.pinnedRequests) {
        requestsById.putIfAbsent(request.id, () => request);
      }
    }
    final drawnRequests = [
      for (final id in drawnRequestIds)
        if (requestsById[id] case final request?) request,
    ]..sort((a, b) => a.id.compareTo(b.id));

    layoutEgoId = _viewer.id;
    layoutVisibleRequestsByAuthor = plan.layoutRequestsByAuthor;
    layoutEgoOwnRequestIds = plan.egoOwnRequestIds;
    displayedRequestIds = plan.drawnRequestIds;
    overflowHiddenCountByAuthor = plan.overflowHiddenCountByAuthor;

    final nodes = <NodeDetails>{};
    final edges = <EdgeDetails<NodeDetails>>{};
    edgeKinds.clear();

    nodes.add(
      FieldPersonNode(
        person: _viewer,
        ring: 0,
        isKept: true,
      ),
    );

    final keptSorted = state.keptPeerIds.toList()..sort();
    for (final peerId in keptSorted) {
      final peer = peersById[peerId];
      if (peer == null) {
        continue;
      }
      final ring = paths.ring.contains(peerId)
          ? kConstellationLayoutMaxHops + 1
          : paths.depth[peerId] ?? kConstellationLayoutMaxHops;
      nodes.add(
        FieldPersonNode(
          person: _profileFromPeer(peer),
          ring: ring,
          isKept: paths.keep.contains(peerId),
        ),
      );
    }

    for (final request in drawnRequests) {
      nodes.add(FieldRequestNode(request: request));
    }

    final nodeById = {for (final node in nodes) node.id: node};

    void addEdge({
      required String srcId,
      required String dstId,
      required ConstellationEdgeKind kind,
    }) {
      final src = nodeById[srcId];
      final dst = nodeById[dstId];
      if (src == null || dst == null) {
        return;
      }
      final edge = EdgeDetails(
        source: src,
        destination: dst,
        color: Colors.transparent,
        strokeWidth: switch (kind) {
          ConstellationEdgeKind.tier1Path => 2,
          ConstellationEdgeKind.tier2Path => 2,
          ConstellationEdgeKind.attachment => 1.5,
          ConstellationEdgeKind.ringStub => 1.5,
        },
      );
      edges.add(edge);
      edgeKinds['$srcId\0$dstId'] = kind;
    }

    for (final child in paths.keep.intersection(state.keptPeerIds)) {
      final parentId = paths.parent[child];
      if (parentId == null) {
        continue;
      }
      final tier = paths.parentTier[child] ?? 1;
      addEdge(
        srcId: parentId,
        dstId: child,
        kind: tier == 1
            ? ConstellationEdgeKind.tier1Path
            : ConstellationEdgeKind.tier2Path,
      );
    }

    for (final ringPeer in paths.ring.intersection(state.keptPeerIds)) {
      addEdge(
        srcId: _viewer.id,
        dstId: ringPeer,
        kind: ConstellationEdgeKind.ringStub,
      );
    }

    for (final request in drawnRequests) {
      addEdge(
        srcId: request.authorId,
        dstId: request.id,
        kind: ConstellationEdgeKind.attachment,
      );
    }

    graphController.clear(recenter: false);
    graphController.useLayoutAlgorithm(mapLayoutAlgorithm);
    graphController.mutate((mutator) {
      for (final node in nodes) {
        mutator.addNode(node);
      }
      for (final edge in edges) {
        mutator.addEdge(edge);
      }
    });
    emit(state.copyWith(graphRevision: state.graphRevision + 1));
  }

  /// [Profile.isMutuallyVisible] (and the "closed eye" copy it drives in the
  /// reused [GraphPersonContextPanel]) is derived from the *old*,
  /// per-direction trust/MeritRank fields (`myVote`, `subjectExplicitlyTrustsViewer`,
  /// `score`/`rScore`) — the exact asymmetric model D14/UNIT04 superseded.
  /// Every peer in `field.peers` is already guaranteed mutually visible by
  /// `person_visible_peers_symmetric` (that guarantee is *why* they're in the
  /// field at all), so defaulting these fields to false — as a bare
  /// `ConstellationPerson`→`Profile` mapping does — makes the panel falsely
  /// claim "no two-way visibility" for every peer. Fix it using only data
  /// Constellation is actually allowed to have without violating wire hygiene
  /// (§9.1 forbids ever setting `score`/`rScore` from this feature — those
  /// are MeritRank-shaped fields and this reused widget may render a score
  /// badge from them elsewhere): if a **tier-1** (explicit `vote_user`) edge
  /// exists between the viewer and this peer in either direction — checked
  /// against `field.edges`, the full closure over the graph peer set, not
  /// just the resolved tree — mark that direction's explicit-trust flag
  /// true. That's an honest, score-free signal, and matches this specific
  /// peer's real data in the common case (a direct, explicit connection).
  /// A peer reached only via a tier-2/derived path, or with no edge to the
  /// viewer in `field.edges` at all (e.g. a request-author-only profile),
  /// still can't honestly be marked "explicit" — that residual case is a
  /// known, documented limitation (see docs/features/constellation.md),
  /// not something to paper over with a fabricated score.
  Profile _profileFromPeer(ConstellationPerson peer) {
    final edges = state.field?.edges ?? const <ConstellationTrustEdgeEntity>[];
    final viewerTrustsSubject = edges.any(
      (e) => e.tier == 1 && e.src == _viewer.id && e.dst == peer.id,
    );
    final subjectTrustsViewer = edges.any(
      (e) => e.tier == 1 && e.src == peer.id && e.dst == _viewer.id,
    );
    return Profile(
      id: peer.id,
      displayName: peer.displayName ?? '',
      handle: peer.handle ?? '',
      image: peer.image,
      myVote: viewerTrustsSubject ? 1 : 0,
      subjectExplicitlyTrustsViewer: subjectTrustsViewer,
    );
  }

  void _replaceRequestInField(ConstellationRequest refreshed) {
    final field = state.field;
    if (field == null) {
      return;
    }
    final requests = [
      for (final request in field.requests)
        if (request.id == refreshed.id) refreshed else request,
    ];
    emit(
      state.copyWith(
        field: field.copyWith(requests: requests),
      ),
    );
    _recomposeAndLayout();
  }

  String _authorizationDeniedMessage(BeaconStatus status) => switch (status) {
    BeaconStatus.cancelled || BeaconStatus.closed || BeaconStatus.reviewOpen =>
      'This request is closed and no longer accepts help.',
    BeaconStatus.deleted => 'This request is no longer available.',
    BeaconStatus.draft => 'This request is not open yet.',
    _ => 'You can no longer act on this request.',
  };

  bool _isOfferKindChanged(Object error) {
    final code = _coordinationCodeFromError(error);
    return code == kOfferKindChangedCoordinationCode;
  }

  bool _isAuthorizationFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('unauthorized') ||
        message.contains('cannot read request content');
  }

  int? _coordinationCodeFromError(Object error) {
    final text = error.toString();
    final match = RegExp(r'code\D*(\d{4})').firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
}
