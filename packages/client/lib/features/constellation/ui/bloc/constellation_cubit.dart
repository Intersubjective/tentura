import 'dart:async';
import 'dart:developer' show TimelineTask;

import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';

import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_density.dart';
import '../../domain/constellation_filters.dart';
import '../../domain/constellation_layout.dart';
import '../../domain/constellation_drag_cluster.dart';
import '../../domain/constellation_pin_position.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../util/layout_geometry_adapters.dart';
import '../../domain/use_case/constellation_member_webs_case.dart';
import '../../domain/entity/placement_outbox.dart';
import '../../domain/placement_overlay.dart';
import '../../domain/use_case/constellation_anchor_case.dart';
import '../../domain/use_case/constellation_placement_case.dart';
import '../../domain/use_case/constellation_field_store_case.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../../graph/ui/utils/tentura_layout_algorithms.dart';
import '../utils/constellation_graph_scene.dart';
import '../scene/constellation_interaction_controller.dart';
import '../scene/constellation_scene_controller.dart';
import '../util/constellation_perf.dart';
import 'constellation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../scene/constellation_scene_controller.dart'
    show ConstellationEdgeKind, kConstellationLayoutMaxHops;
export 'constellation_state.dart';

/// Server `HelpOfferCoordinationExceptionCode.offerKindChanged` wire code.
const kOfferKindChangedCoordinationCode = 1516;

/// User-visible copy when graph layout recovery is exhausted (tests assert this).
const kConstellationGraphLayoutFailureMessage =
    'Could not refresh the map layout. Try again or keep the current view.';

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
    required ConstellationFieldStoreCase case_,
    required Profile viewer,
    this._anchorCase,
    this._placementCase,
    this._memberWebsCase,
    ForwardCase? forwardCase,
    bool loadOnCreate = true,
    this._composePresentation = composeConstellationPresentation,
    ConstellationSceneController? scene,
  }) : _scene = scene ?? ConstellationSceneController(),
       _case = case_,
       _viewer = viewer,
       _forwardCaseOverride = forwardCase,
       super(const ConstellationState()) {
    _anchorLifecycleToken = _anchorCase?.activate(viewerAccountId: viewer.id);
    _storeLease = _case.lease();
    _storeSub = _case.changes.listen(_onStoreChanged);
    _placementSub = _placementCase?.changes.listen(_onPlacementChanged);
    // ignore: invalid_use_of_visible_for_testing_member
    graphController.scene.addListener(_onGraphSceneLayoutOutcomeChanged);
    if (loadOnCreate) {
      unawaited(load());
    }
  }

  final ConstellationFieldStoreCase _case;
  final ConstellationAnchorCase? _anchorCase;
  final ConstellationPlacementCase? _placementCase;
  final ConstellationMemberWebsCase? _memberWebsCase;
  final Profile _viewer;

  /// Lazily fetched member webs per selected Request id (kept for the
  /// cubit's lifetime; a field reload does not invalidate it).
  final Map<String, List<ConstellationMemberWeb>> _requestWebsById = {};
  final Set<String> _requestWebsInFlight = {};
  final ForwardCase? _forwardCaseOverride;

  late final StoreLease _storeLease;
  StreamSubscription<ConstellationFieldStoreState>? _storeSub;
  StreamSubscription<PlacementOutboxState>? _placementSub;

  /// Field (confirmed anchors plus unresolved placement intent) last composed;
  /// an update that leaves its layout inputs unchanged does not re-lay out.
  ConstellationField? _lastPresentationField;
  ConstellationField? _lastAppliedStoreField;
  final ConstellationPresentationComposer _composePresentation;
  int? _anchorLifecycleToken;
  int _layoutReconciliationCount = 0;
  List<TimelineTask>? _dropReflowSpans;
  final ConstellationSceneController _scene;
  ConstellationInteractionController get _interaction => _scene.interaction;

  int _writeCount = 0;

  /// A store publication or an outbox change arrived while the scene was
  /// frozen; the release applies them together in one compose and layout.
  bool _storeInputHeld = false;
  bool _outboxInputHeld = false;

  /// A dropped placement is with the outbox and the store has not published
  /// its settlement yet; its presentation holds must survive a cancel.
  bool _placementAwaitingStore = false;

  ConstellationLayoutPriorHints? _layoutPriorHints;
  Set<String> _forgetPriorHintNodeIds = {};
  bool _layoutRecoveryAttempted = false;
  bool _dispatchingLayoutRecovery = false;

  @visibleForTesting
  SceneLayoutAlgorithm? get testSceneLayoutAlgorithmOverride =>
      _scene.testSceneLayoutAlgorithmOverride;

  @visibleForTesting
  set testSceneLayoutAlgorithmOverride(SceneLayoutAlgorithm? value) =>
      _scene.testSceneLayoutAlgorithmOverride = value;

  Set<String> _composingCandidateIds = const {};
  String? _selectedRequestMemberId;

  Set<String> get _extraKeptPeerIds => {
    ..._composingCandidateIds,
    if (_selectedRequestMemberId != null &&
        _selectedRequestMemberId == state.selectedPersonId)
      _selectedRequestMemberId!,
  };

  Map<String, ConstellationPerson> _composerPeople = const {};
  final Set<String> _composerPlacedPersonIds = {};
  final Map<String, Offset> _composerPersonPositions = {};

  /// Graph ids of people the viewer moved by hand while composing; they stay
  /// where they were dropped until the session ends, over their pins.
  final Set<GraphNodeId> _composerMovedPersonIds = {};

  /// People who had no pin when the viewer first moved them while composing.
  final Set<String> _composerMovedUnpinnedIds = {};

  /// Graph id of the person a composer drag holds, and where it started.
  GraphNodeId? _composerDragGraphId;
  Offset? _composerDragStart;
  Set<String> _composingSelectedIds = const {};
  Offset _composingDraftCentre = Offset.zero;
  void Function(String personId)? _onComposingToggle;

  ForwardCase get _forwardCase =>
      _forwardCaseOverride ?? GetIt.I<ForwardCase>();

  GraphController<NodeDetails, EdgeDetails> get graphController =>
      _scene.graphController;

  Map<GraphEdgeId, ConstellationEdgeKind> get edgeKinds => _scene.edgeKinds;

  Map<String, ConstellationEdgeKind> get edgeKindByPair =>
      _scene.edgeKindByPair;

  Map<String, double> get postFadeById => _scene.postFadeById;

  Map<String, double> get edgeFadeBySemanticId => _scene.edgeFadeBySemanticId;

  Map<String, int> get postOverflowCountByPostId =>
      _scene.postOverflowCountByPostId;

  String get layoutEgoId => _scene.layoutEgoId;

  Map<String, List<String>> get layoutVisibleRequestsByAuthor =>
      _scene.layoutVisibleRequestsByAuthor;

  Set<String> get layoutEgoOwnRequestIds => _scene.layoutEgoOwnRequestIds;

  Set<String> get displayedRequestIds => _scene.displayedRequestIds;

  Map<String, int> get overflowHiddenCountByAuthor =>
      _scene.overflowHiddenCountByAuthor;

  Map<String, int> get expandedExtraCountByAuthor =>
      _scene.expandedExtraCountByAuthor;

  Map<String, ConstellationFootprint> get layoutFootprints =>
      _scene.layoutFootprints;

  Set<String> droppedHolderIds = const {};
  final Set<String> expandedSatelliteAuthorIds = {};

  Size _labelBudgetViewport = const Size(1200, 900);
  double _labelBudgetTextScale = 1;
  ConstellationLabelBudget? _appliedLabelBudget;
  bool _labelBudgetRecomposePending = false;
  ConstellationFootprintMetrics? _footprintMetrics;

  @visibleForTesting
  double get labelBudgetTextScaleForTest => _labelBudgetTextScale;

  @visibleForTesting
  int get layoutReconciliationCount => _layoutReconciliationCount;

  @visibleForTesting
  Set<String> get forgetPriorHintNodeIdsForTest => _forgetPriorHintNodeIds;

  @visibleForTesting
  int get writeCount => _writeCount;

  SceneLayoutAlgorithm get graphSceneLayoutAlgorithm => _scene.layoutAlgorithm(
    graphRevision: state.graphRevision,
    viewerId: _viewer.id,
    statePaths: state.paths,
    stateKeptPeerIds: state.keptPeerIds,
    forgetPriorHintNodeIds: _forgetPriorHintNodeIds,
  );

  ConstellationSceneLayoutAlgorithm get constellationSceneLayoutAlgorithm =>
      _scene.constellationAlgorithm(
        graphRevision: state.graphRevision,
        viewerId: _viewer.id,
        statePaths: state.paths,
        stateKeptPeerIds: state.keptPeerIds,
        forgetPriorHintNodeIds: _forgetPriorHintNodeIds,
      );

  @override
  Future<void> close() async {
    _storeLease.dispose();
    // Not awaited: the store's broadcast stream has no cancel cleanup, so the
    // returned future is the shared root-zone null future. Awaiting it would
    // hop the rest of close() out of the caller's zone (fake-async widget
    // tests then never deliver the state stream's done event).
    unawaited(_storeSub?.cancel());
    _storeSub = null;
    unawaited(_placementSub?.cancel());
    _placementSub = null;
    _clearClusterPresentations();
    _finishDropReflowSpans();
    // ignore: invalid_use_of_visible_for_testing_member
    graphController.scene.removeListener(_onGraphSceneLayoutOutcomeChanged);
    _anchorCase?.deactivate(token: _anchorLifecycleToken);
    _scene.dispose();
    return super.close();
  }

  /// Screen visibility contributes to the shared store's lease visibility.
  void setVisible(bool visible) {
    if (!isClosed) _storeLease.setVisible(visible);
  }

  void _onStoreChanged(ConstellationFieldStoreState snapshot) {
    if (isClosed) return;
    final field = snapshot.field;
    if (field == null) {
      if (state.field != null) onAccountChanged();
      return;
    }
    if (identical(field, _lastAppliedStoreField)) return;
    if (_scene.isFrozen) {
      // The data is current; composing and laying it out wait for the release.
      _storeInputHeld = true;
      emit(state.copyWith(field: _adoptStoreField(field)));
      return;
    }
    _applyLoadedField(field);
  }

  void retryGraphLayoutAfterFailure() {
    if (isClosed || state.graphLayoutFailureMessage == null) {
      return;
    }
    _layoutRecoveryAttempted = false;
    emit(state.copyWith(graphLayoutFailureMessage: null));
    _scene.awaitingLayoutOutcome = true;
    _scene.scheduleLayoutRecoveryAfterRebuild = true;
    _reconcileLayout();
  }

  void cancelGraphLayoutFailure() {
    if (isClosed || state.graphLayoutFailureMessage == null) {
      return;
    }
    emit(state.copyWith(graphLayoutFailureMessage: null));
  }

  @visibleForTesting
  void requestConstellationLayoutForTest({
    SceneLayoutAlgorithm? algorithm,
    bool bumpGraphRevision = true,
  }) {
    _scene.ephemeralOwnedLayoutAlgorithm = algorithm;
    _scene.awaitingLayoutOutcome = true;
    _scene.scheduleLayoutRecoveryAfterRebuild = false;
    if (isClosed) {
      return;
    }
    if (bumpGraphRevision) {
      emit(state.copyWith(graphRevision: state.graphRevision + 1));
    }
    runAfterNextFrame(() {
      if (isClosed ||
          _scene.ephemeralOwnedLayoutAlgorithm == null ||
          state.graphLayoutFailureMessage != null) {
        return;
      }
      _scene.awaitingLayoutOutcome = true;
      _scene.requestLayout(
        releaseOnTerminal: _scene.activePresentationReleaseTokens(),
        algorithm: graphSceneLayoutAlgorithm,
      );
    });
  }

  void _onGraphSceneLayoutOutcomeChanged() {
    if (isClosed || _dispatchingLayoutRecovery) {
      return;
    }
    // ignore: invalid_use_of_visible_for_testing_member
    final outcome = graphController.scene.layoutOutcome;
    if (outcome is GraphLayoutOutcomeRunning) {
      return;
    }
    if (!_scene.awaitingLayoutOutcome) {
      return;
    }
    _scene.awaitingLayoutOutcome = false;

    if (!kReleaseMode &&
        (outcome is GraphLayoutOutcomeSucceeded ||
            outcome is GraphLayoutOutcomeFailed)) {
      _finishDropReflowSpans();
    }
    if (outcome is GraphLayoutOutcomeSucceeded) {
      _layoutRecoveryAttempted = false;
      if (_forgetPriorHintNodeIds.isNotEmpty) {
        _forgetPriorHintNodeIds = {};
      }
      if (state.graphLayoutFailureMessage != null) {
        emit(state.copyWith(graphLayoutFailureMessage: null));
      }
      return;
    }
    if (outcome is! GraphLayoutOutcomeFailed) {
      return;
    }
    if (state.graphLayoutFailureMessage != null) {
      return;
    }
    final presentation = graphController.renderSnapshot.presentation;
    if (presentation.holds.isNotEmpty || presentation.overrides.isNotEmpty) {
      _scene.ephemeralOwnedLayoutAlgorithm = null;
      return;
    }

    if (_layoutRecoveryAttempted) {
      _scene.layoutHandoffGeneration++;
      _scene.scheduleLayoutRecoveryAfterRebuild = false;
      emit(
        state.copyWith(
          graphLayoutFailureMessage: kConstellationGraphLayoutFailureMessage,
        ),
      );
      return;
    }

    _layoutRecoveryAttempted = true;
    _scene.ephemeralOwnedLayoutAlgorithm = null;
    unawaited(_recoverGraphLayoutFromConfirmedProjection());
  }

  Future<void> _recoverGraphLayoutFromConfirmedProjection() async {
    if (isClosed) {
      return;
    }
    _dispatchingLayoutRecovery = true;
    try {
      await _mergeConfirmedProjection(_anchorCase?.confirmedProjection);
    } finally {
      _dispatchingLayoutRecovery = false;
    }
    if (isClosed) {
      return;
    }
    _scene.scheduleLayoutRecoveryAfterRebuild = true;
    _scene.awaitingLayoutOutcome = true;
    _reconcileLayout();
  }

  Future<void> load() async {
    if (isClosed) return;
    final generation = state.loadGeneration + 1;
    emit(
      state.copyWith(
        status: const StateIsLoading(),
        loadError: null,
        loadGeneration: generation,
      ),
    );
    _case.setMembershipFilters(state.membershipFilters);
    try {
      await _case.requestRefresh(ConstellationRefreshReason.load);
      if (isClosed || generation != state.loadGeneration) return;
      final field = _case.current.field;
      if (field != null && !identical(field, _lastAppliedStoreField)) {
        _applyLoadedField(field);
      } else {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } on Object catch (error) {
      if (!isClosed && generation == state.loadGeneration) {
        emit(state.copyWith(status: const StateIsSuccess(), loadError: error));
      }
    }
  }

  void _applyLoadedField(ConstellationField field) {
    _lastAppliedStoreField = field;
    _placementAwaitingStore = false;
    final labelBudget = _currentLabelBudget();
    final loadedField = _adoptStoreField(field);
    final confirmedProjection = loadedField.resolvedAnchorProjection;
    final deferTargets = _shouldDeferPlacementRefresh()
        ? _draggedTargetsForPresentation()
        : const <ConstellationAnchorTarget>{};
    if (deferTargets.isEmpty) _noteDisappearedAnchors(confirmedProjection);
    final presentationField = _desiredField(
      deferTargets.isEmpty
          ? loadedField
          : loadedField.copyWith(
              anchorProjection: _presentationProjection(
                confirmedProjection,
                deferTargets: deferTargets,
              ),
            ),
    );
    final unchangedLayout = _sameLayoutInputs(
      _lastPresentationField,
      presentationField,
    );
    _lastPresentationField = presentationField;
    final composition = kReleaseMode
        ? _composePresentation(
            viewerId: _viewer.id,
            field: _composerField(presentationField),
            localFilters: state.filters,
            asOfUtc: loadedField.loadedAt,
            labelBudget: labelBudget,
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _selectedRequestWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(presentationField),
              localFilters: state.filters,
              asOfUtc: loadedField.loadedAt,
              labelBudget: labelBudget,
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _selectedRequestWebs,
              extraKeptPeerIds: _extraKeptPeerIds,
            ),
          );
    emit(
      state.copyWith(
        status: const StateIsSuccess(),
        loadedAt: loadedField.loadedAt,
        field: loadedField,
        composition: composition,
        paths: composition.paths,
        keptPeerIds: composition.keptPeerIds,
        capped: composition.renderBudgetCapped,
        loadError: null,
        syncPending: _anchorCase?.syncPending ?? false,
      ),
    );
    droppedHolderIds = composition.droppedHolderIds;
    _reconcileSelection(composition);
    if (deferTargets.isEmpty && !unchangedLayout) {
      _reconcileLayout(immediateHandoff: true);
    }
  }

  /// [field] with the anchors the anchor case holds as confirmed.
  ConstellationField _adoptStoreField(ConstellationField field) {
    final adopted =
        _anchorCase?.adoptConfirmedProjection(
          field.resolvedAnchorProjection,
        ) ??
        true;
    final confirmedProjection =
        _anchorCase?.confirmedProjection ?? field.resolvedAnchorProjection;
    return adopted
        ? field
        : field.copyWith(anchorProjection: confirmedProjection);
  }

  /// The field with unresolved placement intent laid over its confirmed anchors.
  ConstellationField _desiredField(ConstellationField field) {
    final placement = _placementCase;
    if (placement == null) return field;
    return field.copyWith(
      anchorProjection: desiredAnchorProjection(
        field.resolvedAnchorProjection,
        placement.current,
        now: DateTime.now(),
      ).projection,
    );
  }

  /// Whether laying out [next] would give the scene nothing new over [previous].
  bool _sameLayoutInputs(
    ConstellationField? previous,
    ConstellationField next,
  ) {
    if (previous == null || state.composition == null) return false;
    final before = previous.resolvedAnchorProjection;
    final after = next.resolvedAnchorProjection;
    return previous.copyWith(anchorProjection: null) ==
            next.copyWith(anchorProjection: null) &&
        listEquals(before.pinnedPeers, after.pinnedPeers) &&
        listEquals(before.pinnedRequests, after.pinnedRequests) &&
        listEquals(before.supportPeers, after.supportPeers) &&
        listEquals(before.supportEdges, after.supportEdges) &&
        listEquals(
          before.serverFilteredBeaconIds,
          after.serverFilteredBeaconIds,
        ) &&
        before.serverFilteredBeaconCount == after.serverFilteredBeaconCount &&
        before.anchors.length == after.anchors.length &&
        {for (final a in before.anchors) a.target: a.position}.entries.every(
          (entry) => after.anchors.any(
            (a) => a.target == entry.key && a.position == entry.value,
          ),
        );
  }

  /// Unresolved placement intent is composed before the server answers.
  void _onPlacementChanged(PlacementOutboxState _) {
    if (isClosed || state.field == null) return;
    if (_scene.isFrozen) {
      _outboxInputHeld = true;
      return;
    }
    _composeOutboxChange();
  }

  void _composeOutboxChange() {
    final field = state.field;
    if (isClosed || field == null) return;
    // A store publication still queued reads the outbox itself when it lands.
    if (!identical(_case.current.field, _lastAppliedStoreField)) return;
    final presentationField = _desiredField(field);
    if (_sameLayoutInputs(_lastPresentationField, presentationField)) return;
    _lastPresentationField = presentationField;
    _noteDisappearedAnchors(presentationField.resolvedAnchorProjection);
    final composition = _composePresentation(
      viewerId: _viewer.id,
      field: _composerField(presentationField),
      localFilters: state.filters,
      asOfUtc: state.loadedAt ?? field.loadedAt,
      labelBudget: _currentLabelBudget(),
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
      selectedRequestWebs: _selectedRequestWebs,
      extraKeptPeerIds: _extraKeptPeerIds,
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
    _reconcileLayout(deferAutomaticReflow: true, immediateHandoff: true);
  }

  String get viewerId => _viewer.id;

  Profile get viewer => _viewer;

  Future<void> onAccountChanged() async {
    if (isClosed) {
      return;
    }
    if (state.isComposing) exitComposing();
    _storeInputHeld = false;
    _outboxInputHeld = false;
    _cancelUnsentPlacement(write: false, force: true);
    final generation =
        _anchorCase?.onAccountChanged() ?? state.loadGeneration + 1;
    _anchorLifecycleToken =
        _anchorCase?.activate(viewerAccountId: _viewer.id) ?? generation;
    emit(
      state.copyWith(
        loadGeneration: generation,
        isComposing: false,
        field: null,
        composition: null,
        paths: null,
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: null,
        placementFailureMessage: null,
        syncPending: false,
      ),
    );
    _clearClusterPresentations();
  }

  void beginDragExisting({
    required ConstellationAnchorTarget target,
  }) {
    if (isClosed) {
      return;
    }
    _interaction.beginDragging(target.graphNodeId);
    _beginClusterDragPresentation(target);
    graphController.setCameraInteractionGated(true);
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.draggingExisting,
        activePlacementTarget: target,
        placementFailureMessage: null,
      ),
    );
  }

  void beginDragNew({required ConstellationAnchorTarget target}) {
    if (isClosed) {
      return;
    }
    _interaction.beginDragging(target.graphNodeId);
    _beginClusterDragPresentation(target);
    graphController.setCameraInteractionGated(true);
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.draggingNew,
        activePlacementTarget: target,
        placementFailureMessage: null,
      ),
    );
  }

  /// People the composer may address (field peers and forward candidates,
  /// except the viewer) and their current scene positions; people the graph
  /// does not show have none.
  Future<({Map<String, Offset> positions, Set<String> eligible})>
  composerPeople() async {
    final eligible = <String>{
      for (final p in state.field?.peers ?? const <ConstellationPerson>[]) p.id,
    };
    try {
      final candidates = await _forwardCase.fetchForwardCandidates(
        context: state.field?.context ?? '',
      );
      final profiles = candidates.toList();
      eligible.addAll(profiles.map((p) => p.id));
      _composerPeople = {
        for (final p in profiles)
          p.id: ConstellationPerson(
            id: p.id,
            displayName: p.displayName,
            handle: p.handle,
            image: p.image,
          ),
      };
    } on Object {
      // The field peers alone are still a usable audience.
    }
    eligible.remove(_viewer.id);
    final snapshot = graphController.renderSnapshot;
    final positions = <String, Offset>{};
    for (final id in eligible) {
      final point = snapshot.resolvePosition('fp:$id');
      if (point != null) positions[id] = Offset(point.x, point.y);
    }
    return (positions: positions, eligible: eligible);
  }

  String composerPersonName(String id) {
    final candidate = _composerPeople[id];
    if (candidate?.displayName?.isNotEmpty ?? false) {
      return candidate!.displayName!;
    }
    for (final person in state.field?.peers ?? const <ConstellationPerson>[]) {
      if (person.id == id && (person.displayName?.isNotEmpty ?? false)) {
        return person.displayName!;
      }
    }
    return id;
  }

  /// Enters the composing phase: adds the draft node at [draftCentre], widens
  /// the composition to [candidateIds] (all addressable people) and draws a draft
  /// edge to every id in [selectedIds]. Existing nodes keep their positions.
  void enterComposing({
    required Offset draftCentre,
    required Set<String> candidateIds,
    required Set<String> selectedIds,
    required void Function(String personId) onToggle,
  }) {
    if (isClosed || state.field == null) {
      return;
    }
    _composingCandidateIds = candidateIds;
    _composingSelectedIds = selectedIds;
    _composingDraftCentre = draftCentre;
    _onComposingToggle = onToggle;
    emit(
      state.copyWith(
        isComposing: true,
        placementPhase: state.hasPendingPlacementWrite
            ? state.placementPhase
            : ConstellationPlacementPhase.composing,
        viewMode: ConstellationViewMode.map,
        selectedPersonId: null,
        selectedRequestId: null,
      ),
    );
    _recomposeAndLayout();
  }

  /// Follows the composer's circle: moves the draft node and redraws the
  /// selection through the interaction layer only — no recomposition, no
  /// layout.
  void followComposer({
    required Offset draftCentre,
    required Set<String> selectedIds,
  }) {
    if (isClosed || !state.isComposing) {
      return;
    }
    _composingDraftCentre = draftCentre;
    _scene.placeDraftNode(draftCentre);
    if (!setEquals(_composingSelectedIds, selectedIds)) {
      _composingSelectedIds = selectedIds;
      _rebuildGraphWithoutLayout();
    }
  }

  /// Leaves the composing phase: removes the draft node and its edges and
  /// restores the regular composition.
  ///
  /// People moved by hand return to their places, except those in
  /// [pinPersonIds] who had no pin: they get one where they were dropped.
  void exitComposing({Set<String> pinPersonIds = const {}}) {
    if (isClosed || !state.isComposing) {
      return;
    }
    if (_composerDragGraphId != null) _cancelComposerDrag();
    final token = graphController.activePresentationTokenForNode(
      const FieldDraftNode().graphNodeId,
    );
    if (token != null) {
      graphController.cancelNodePresentationDrag(token);
    }
    final pinnedGraphIds = <GraphNodeId>{};
    if (_placementCase != null) {
      for (final id in _composerMovedUnpinnedIds.intersection(pinPersonIds)) {
        final graphId = 'fp:$id';
        final position = _composerPersonPositions[graphId];
        if (position == null) continue;
        _submitUpsert(
          target: ConstellationAnchorTarget.person(id),
          position: constellationPointToV1Anchor(
            (x: position.dx, y: position.dy),
          ),
        );
        pinnedGraphIds.add(graphId);
      }
    }
    _composerPlacedPersonIds
        .difference(pinnedGraphIds)
        .forEach(graphController.clearPresentationForNodeId);
    // A new pin holds its node at the drop until the layout lands there.
    if (pinnedGraphIds.isNotEmpty) {
      _scene.addPlacementHandoffGraphIds(pinnedGraphIds);
    }
    _composerPlacedPersonIds.clear();
    _composerPersonPositions.clear();
    _composerMovedPersonIds.clear();
    _composerMovedUnpinnedIds.clear();
    _composingCandidateIds = const {};
    _composingSelectedIds = const {};
    _onComposingToggle = null;
    emit(
      state.copyWith(
        isComposing: false,
        placementPhase: state.hasPendingPlacementWrite
            ? state.placementPhase
            : ConstellationPlacementPhase.idle,
      ),
    );
    _recomposeAndLayout();
  }

  /// Places the draft node, which is not in the anchor set, at a fixed centre.
  void updateDragPresentation({
    required String nodeId,
    required Offset sceneCentre,
  }) {
    if (isClosed) {
      return;
    }
    final target = state.activePlacementTarget;
    if (target == null) {
      return;
    }
    // The held node is named by its domain id (gesture layer) or graph id.
    final dragging = _interaction.draggingNodeId;
    if (dragging == null ||
        (dragging != nodeId &&
            nodeId != constellationGraphNodeIdForTarget(target))) {
      return;
    }
    _interaction.updateDragPresentation(target, sceneCentre);
  }

  Offset clampClusterDragPosition(NodeDetails node, Offset proposed) {
    final composerStart = _composerDragStart;
    if (composerStart != null &&
        tenturaGraphNodeId(node) == _composerDragGraphId) {
      return _clampComposerDrop(composerStart, proposed);
    }
    return _interaction.clampClusterDragPosition(
      state.activePlacementTarget,
      node,
      proposed,
    );
  }

  /// Whether dragging [node] only moves it for the composer session: while
  /// composing, people are arranged by hand and nothing is written.
  bool isComposerDrag(NodeDetails node) =>
      state.isComposing && node is FieldPersonNode && node.id != viewerId;

  /// Whether a composer drag holds a node.
  bool get isComposerDragActive => _composerDragGraphId != null;

  void beginComposerDrag(FieldPersonNode node) {
    if (isClosed || !state.isComposing) {
      return;
    }
    final graphId = node.graphNodeId;
    final point = graphController.renderSnapshot.resolvePosition(graphId);
    _composerDragGraphId = graphId;
    _composerDragStart =
        _composerPersonPositions[graphId] ??
        (point == null ? null : Offset(point.x, point.y));
    if (!_composerMovedPersonIds.contains(graphId) &&
        !isAnchored(ConstellationAnchorTarget.person(node.id))) {
      _composerMovedUnpinnedIds.add(node.id);
    }
    _interaction.beginDragging(node.id);
  }

  /// Keeps the person where it was dropped for the rest of the session.
  void endComposerDrag(FieldPersonNode node, Offset sceneCentre) {
    final graphId = node.graphNodeId;
    if (isClosed || _composerDragGraphId != graphId) {
      return;
    }
    final start = _composerDragStart;
    final drop = start == null
        ? sceneCentre
        : _clampComposerDrop(start, sceneCentre);
    _composerDragGraphId = null;
    _composerDragStart = null;
    _interaction.draggingNodeId = null;
    _composerMovedPersonIds.add(graphId);
    _composerPlacedPersonIds.add(graphId);
    _composerPersonPositions[graphId] = drop;
    _scene.updateSingleNodePresentation(graphId, drop);
    graphController.setCameraInteractionGated(false);
    _releaseFreeze();
  }

  /// A lost pointer puts the person back where the drag started.
  void _cancelComposerDrag() {
    final graphId = _composerDragGraphId;
    final start = _composerDragStart;
    _composerDragGraphId = null;
    _composerDragStart = null;
    _interaction.draggingNodeId = null;
    if (graphId != null && start != null) {
      _scene.updateSingleNodePresentation(graphId, start);
    }
    graphController.setCameraInteractionGated(false);
    _releaseFreeze();
  }

  Offset _clampComposerDrop(Offset start, Offset proposed) {
    final limited = constellationLimitClusterDelta(
      parentStart: (x: start.dx, y: start.dy),
      proposedParent: (x: proposed.dx, y: proposed.dy),
      companionStarts: const [],
    );
    return Offset(start.dx + limited.x, start.dy + limited.y);
  }

  void _beginClusterDragPresentation(ConstellationAnchorTarget target) =>
      _interaction.beginClusterDragPresentation(
        target,
        field: state.field,
        composition: state.composition,
        fallbackAnchors: [
          ...?state.composition?.anchorOverlay.anchors,
          ...?state.confirmedProjection?.anchors,
        ],
      );

  void _finishDropReflowSpans() {
    if (kReleaseMode) return;
    (_dropReflowSpans ?? const <TimelineTask>[]).forEach(
      ConstellationPerf.finishSpan,
    );
    _dropReflowSpans = null;
  }

  Future<void> onExistingNodeDrop({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) async {
    if (isClosed || _interaction.suppressLateGestureEnd) return;
    if (kReleaseMode) {
      await _dropNode(target: target, sceneCentre: sceneCentre);
      return;
    }
    final draggable = ConstellationPerf.startSpan(
      'constellation.drop→draggable',
    );
    final ack = ConstellationPerf.startSpan('drop→acked');
    final reflow = ConstellationPerf.startSpan('drop→reflowed');
    var handedOff = false;
    try {
      await _dropNode(
        target: target,
        sceneCentre: sceneCentre,
        draggableSpan: draggable,
        ackSpan: ack,
      );
      if (!isClosed && !state.isComposing && reflow != null) {
        (_dropReflowSpans ??= <TimelineTask>[]).add(reflow);
        handedOff = true;
      }
    } finally {
      if (!handedOff) ConstellationPerf.finishSpan(reflow);
    }
  }

  Future<void> _dropNode({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
    TimelineTask? draggableSpan,
    TimelineTask? ackSpan,
  }) async {
    if (isClosed || _interaction.suppressLateGestureEnd) {
      return;
    }
    if (_isRevokedWhileHeld(target)) {
      // The viewer can no longer see the node, so the drop is not written.
      _cancelUnsentPlacement(write: false, suppressLateGestureEnd: false);
      return;
    }
    _holdDropPresentation(target: target, sceneCentre: sceneCentre);
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    final parentStart = _interaction.clusterStartCentres[parentGraphId];
    final parentNode = graphController.nodePayloadForId(parentGraphId);
    final dropCentre = parentStart == null || parentNode is! NodeDetails
        ? sceneCentre
        : clampClusterDragPosition(parentNode, sceneCentre);
    final position = constellationPointToV1Anchor(
      (x: dropCentre.dx, y: dropCentre.dy),
    );
    final projectionAnchors =
        _anchorCase?.confirmedProjection.anchors ??
        state.confirmedProjection?.anchors ??
        const <ConstellationAnchor>[];
    final remotePinnedBeaconIds = constellationPinnedBeaconIds(
      projectionAnchors,
    );
    final parentDelta = parentStart == null
        ? Offset.zero
        : dropCentre - parentStart;
    final companions =
        <
          ({
            ConstellationAnchorTarget target,
            ConstellationAnchorPosition position,
          })
        >[];
    final droppedCompanionGraphIds = <GraphNodeId>[];
    for (final entry in _interaction.placementClusterTargets.entries) {
      if (entry.key == parentGraphId) {
        continue;
      }
      if (!remotePinnedBeaconIds.contains(entry.value.id)) {
        droppedCompanionGraphIds.add(entry.key);
        continue;
      }
      final start = _interaction.clusterStartCentres[entry.key];
      if (start == null) {
        continue;
      }
      final centre = _interaction.clusterCentreFor(
        entry.key,
        parentGraphId,
        (x: parentDelta.dx, y: parentDelta.dy),
      );
      final companionTarget = entry.value;
      companions.add((
        target: companionTarget,
        position: constellationPointToV1Anchor((x: centre.dx, y: centre.dy)),
      ));
    }
    for (final graphId in droppedCompanionGraphIds) {
      graphController.clearPresentationForNodeId(graphId);
      _interaction.placementClusterGraphIds.remove(graphId);
      _interaction.placementClusterTargets.remove(graphId);
      _interaction.clusterStartCentres.remove(graphId);
    }
    _interaction.placementClusterGraphIds.add(parentGraphId);
    _interaction.placementClusterTargets.putIfAbsent(
      parentGraphId,
      () => target,
    );
    // Keep holds of an earlier drop whose write has not settled yet.
    _scene.addPlacementHandoffGraphIds(_interaction.placementClusterGraphIds);
    _interaction.draggingNodeId = null;
    // The pointer drag has ended; the outbox owns the write from here, so
    // dragging re-enables at once.
    graphController.setCameraInteractionGated(false);
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: target,
      ),
    );
    if (!kReleaseMode) ConstellationPerf.finishSpan(draggableSpan);
    _submitUpsert(
      ackSpan: ackSpan,
      target: target,
      position: position,
      companions: companions,
    );
    // The placement is with the outbox first; the release then composes it
    // together with whatever was held during the drag.
    if (_releaseFreeze() && _placementCase != null) {
      _placementAwaitingStore = true;
    }
  }

  /// Whether a store publication held during the drag no longer has [target]
  /// on the viewer's field.
  bool _isRevokedWhileHeld(ConstellationAnchorTarget target) {
    final field = _case.current.field;
    if (!_storeInputHeld || field == null) return false;
    final projection = field.resolvedAnchorProjection;
    return switch (target.kind) {
      ConstellationAnchorTargetKind.person =>
        !field.peers.any((p) => p.id == target.id) &&
            !projection.pinnedPeers.any((p) => p.id == target.id),
      ConstellationAnchorTargetKind.beacon =>
        !field.requests.any((r) => r.id == target.id) &&
            !field.posts.any((p) => p.id == target.id) &&
            !projection.pinnedRequests.any((r) => r.id == target.id),
    };
  }

  /// Leaves the freeze and applies the inputs held during it in one compose
  /// and layout; returns whether there were any.
  bool _releaseFreeze() {
    _scene.releaseFreeze();
    final storeHeld = _storeInputHeld;
    final outboxHeld = _outboxInputHeld;
    _storeInputHeld = false;
    _outboxInputHeld = false;
    if (isClosed) return false;
    final field = _case.current.field;
    if (storeHeld &&
        field != null &&
        !identical(field, _lastAppliedStoreField)) {
      _applyLoadedField(field);
    } else if (outboxHeld || storeHeld) {
      _composeOutboxChange();
    } else {
      return false;
    }
    _labelBudgetRecomposePending = false;
    return true;
  }

  Future<void> onNewNodeDrop({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) async {
    await onExistingNodeDrop(target: target, sceneCentre: sceneCentre);
  }

  void _holdDropPresentation({
    required ConstellationAnchorTarget target,
    required Offset sceneCentre,
  }) {
    final parentGraphId = constellationGraphNodeIdForTarget(target);
    if (graphController.nodePayloadForId(parentGraphId) == null) {
      return;
    }
    if (_interaction.placementClusterGraphIds.isEmpty) {
      _scene.updateSingleNodePresentation(parentGraphId, sceneCentre);
      return;
    }
    final parentStart = _interaction.clusterStartCentres[parentGraphId];
    if (parentStart == null) {
      return;
    }
    final node = graphController.nodePayloadForId(parentGraphId)!;
    final dropCentre = clampClusterDragPosition(node, sceneCentre);
    final limited = constellationLimitClusterDelta(
      parentStart: (x: parentStart.dx, y: parentStart.dy),
      proposedParent: (x: dropCentre.dx, y: dropCentre.dy),
      companionStarts: _interaction.companionClusterStarts(parentGraphId),
    );
    final updates = <GraphPresentationToken, Offset>{};
    for (final graphId in _interaction.placementClusterGraphIds) {
      final start = _interaction.clusterStartCentres[graphId];
      if (start == null) {
        continue;
      }
      final centre = _interaction.clusterCentreFor(
        graphId,
        parentGraphId,
        limited,
      );
      final token = graphController.activePresentationTokenForNode(graphId);
      if (token != null) {
        updates[token] = centre;
      } else {
        graphController.beginNodePresentationDragForId(graphId, centre);
      }
    }
    if (updates.isNotEmpty) {
      graphController.updateNodePresentationDrags(updates);
    }
  }

  Future<void> pinFromText({required ConstellationAnchorTarget target}) async {
    if (isClosed) {
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
      footprints: layoutFootprints,
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
      ),
    );
    _submitUpsert(target: target, position: position);
  }

  Future<void> unpinAnchor({required ConstellationAnchorTarget target}) async {
    if (isClosed || _placementCase == null) {
      return;
    }
    _writeCount++;
    _placementCase.unpin(target);
  }

  /// Fires whenever a placement write changes state; empty without a case.
  Stream<PlacementOutboxState> get placementChanges =>
      _placementCase?.changes ?? const Stream.empty();

  /// One event per overdue placement acknowledgement; empty without a case.
  Stream<LazyWriteNotice> get lazyWriteNotices =>
      _placementCase?.lazyWriteNotices ?? const Stream.empty();

  /// Nodes whose placement write the user should be told about.
  ({Map<ConstellationAnchorTarget, PlacementCue> cues, Duration? nextChange})
  get placementCues =>
      _placementCase?.cues ??
      (
        cues: const <ConstellationAnchorTarget, PlacementCue>{},
        nextChange: null,
      );

  void retryPlacement(ConstellationAnchorTarget target) {
    if (!isClosed) _placementCase?.retry(target);
  }

  void discardPlacement(ConstellationAnchorTarget target) {
    if (!isClosed) _placementCase?.discard(target);
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
    if (isClosed || _interaction.draggingNodeId == null) {
      return;
    }
    if (_composerDragGraphId != null) {
      _cancelComposerDrag();
      return;
    }
    _cancelUnsentPlacement(write: false);
  }

  /// A hidden tab loses its pointer: a drag in progress ends as a cancel.
  void onTabHidden() => onPointerCancelDuringDrag();

  /// Hands the placement to the outbox; the store publishes its settlement.
  void _submitUpsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
    TimelineTask? ackSpan,
    List<
          ({
            ConstellationAnchorTarget target,
            ConstellationAnchorPosition position,
          })
        >
        companions =
        const [],
  }) {
    if (_placementCase == null) {
      return;
    }
    _writeCount++;
    _placementAwaitingStore = true;
    _placementCase.place(
      parent: target,
      position: position,
      companions: companions,
    );
    if (!kReleaseMode) {
      _finishAckSpanOnSettlement(ackSpan, {
        target,
        for (final companion in companions) companion.target,
      });
    }
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: null,
        placementFailureMessage: null,
      ),
    );
  }

  /// Ends the drop-to-ack span once the outbox has settled these targets.
  void _finishAckSpanOnSettlement(
    TimelineTask? ackSpan,
    Set<ConstellationAnchorTarget> targets,
  ) {
    if (ackSpan == null) {
      return;
    }
    bool settled(PlacementOutboxState outbox) => targets.every((target) {
      final slots = outbox.targets[target];
      return slots?.inFlight == null && slots?.latestPending == null;
    });
    unawaited(
      _placementCase!.changes
          .firstWhere(settled)
          .then<void>(
            (_) => ConstellationPerf.finishSpan(ackSpan),
            onError: (Object _) => ConstellationPerf.finishSpan(ackSpan),
          ),
    );
  }

  void _noteDisappearedAnchors(ConstellationAnchorProjection? incoming) {
    final previousAnchors =
        state.composition?.anchorOverlay.anchors ??
        state.confirmedProjection?.anchors ??
        const <ConstellationAnchor>[];
    if (previousAnchors.isEmpty) {
      return;
    }
    final incomingIds = {
      for (final anchor in incoming?.anchors ?? const <ConstellationAnchor>[])
        anchor.target.id,
    };
    final forgotten = <String>{
      for (final anchor in previousAnchors)
        if (!incomingIds.contains(anchor.target.id)) anchor.target.id,
    };
    if (forgotten.isEmpty) {
      return;
    }
    _forgetPriorHintNodeIds = {..._forgetPriorHintNodeIds, ...forgotten};
  }

  bool _shouldDeferPlacementRefresh() {
    final target = state.activePlacementTarget;
    if (target == null) {
      return false;
    }
    return state.hasPendingPlacementWrite;
  }

  Set<ConstellationAnchorTarget> _draggedTargetsForPresentation() {
    if (_interaction.placementClusterTargets.isNotEmpty) {
      return _interaction.placementClusterTargets.values.toSet();
    }
    final active = state.activePlacementTarget;
    if (active != null) {
      return {active};
    }
    return const {};
  }

  ConstellationAnchorProjection _presentationProjection(
    ConstellationAnchorProjection incoming, {
    Set<ConstellationAnchorTarget> deferTargets = const {},
  }) {
    if (deferTargets.isEmpty) {
      return incoming;
    }
    final baseline = state.field?.resolvedAnchorProjection;
    if (baseline == null) {
      return incoming;
    }
    final baselineByTarget = {
      for (final anchor in baseline.anchors) anchor.target: anchor,
    };
    final anchors = [
      for (final anchor in incoming.anchors)
        if (deferTargets.contains(anchor.target))
          baselineByTarget[anchor.target] ?? anchor
        else
          anchor,
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
    Set<ConstellationAnchorTarget> deferTargets = const {},
  }) async {
    final confirmed = projection ?? _anchorCase?.confirmedProjection;
    final field = state.field;
    if (confirmed == null || field == null) {
      return;
    }
    if (deferTargets.isEmpty) {
      _noteDisappearedAnchors(confirmed);
    }
    final presentation = _presentationProjection(
      confirmed,
      deferTargets: deferTargets,
    );
    final mergedField = field.copyWith(anchorProjection: presentation);
    final composition = kReleaseMode
        ? _composePresentation(
            viewerId: _viewer.id,
            field: _composerField(mergedField),
            localFilters: state.filters,
            asOfUtc: state.loadedAt ?? field.loadedAt,
            labelBudget: _currentLabelBudget(),
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _selectedRequestWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(mergedField),
              localFilters: state.filters,
              asOfUtc: state.loadedAt ?? field.loadedAt,
              labelBudget: _currentLabelBudget(),
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _selectedRequestWebs,
              extraKeptPeerIds: _extraKeptPeerIds,
            ),
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
    _labelBudgetRecomposePending = false;
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
    bool force = false,
  }) {
    if (!force && _placementAwaitingStore && !state.hasPendingPlacementWrite) {
      return;
    }
    if (suppressLateGestureEnd) {
      _interaction.suppressLateGestureEnd = true;
    }
    final target = state.activePlacementTarget;
    if (target != null) {
      _clearDragPresentation(target.graphNodeId);
    } else {
      _clearClusterPresentations();
    }
    graphController.setCameraInteractionGated(false);
    final wasFrozen = _scene.isFrozen;
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.idle,
        activePlacementTarget: null,
        placementFailureMessage: null,
      ),
    );
    if (_releaseFreeze() || write) return;
    if (_labelBudgetRecomposePending) {
      _labelBudgetRecomposePending = false;
      _recomposeAndLayout();
    } else if (!wasFrozen || state.isComposing) {
      // A composer drag has no layout run to wait for, but its nodes are
      // placed again by the rebuild.
      _reconcileLayout();
    }
  }

  void _clearDragPresentation(String nodeId) {
    if (_interaction.placementClusterGraphIds.isNotEmpty) {
      _clearClusterPresentations();
      return;
    }
    final target = state.activePlacementTarget;
    final graphId = target != null && target.graphNodeId == nodeId
        ? constellationGraphNodeIdForTarget(target)
        : constellationGraphNodeIdForDomain(nodeId);
    graphController.clearPresentationForNodeId(graphId);
    _interaction.draggingNodeId = null;
    _scene.clearPlacementHandoffGraphIds();
  }

  void _clearClusterPresentations() {
    _interaction
      ..clearClusterPresentations()
      ..draggingNodeId = null;
  }

  void selectRequest(String? requestId) {
    if (isClosed) {
      return;
    }
    final previousId = state.selectedRequestId;
    final previousMemberId = _selectedRequestMemberId;
    if (requestId != null) {
      _selectedRequestMemberId = null;
    }
    emit(
      state.copyWith(
        selectedRequestId: requestId,
        selectedPersonId: requestId != null ? null : state.selectedPersonId,
      ),
    );
    if (requestId != null) {
      unawaited(_fetchRequestWebs(requestId));
    }
    if (previousMemberId != _selectedRequestMemberId ||
        _selectionAddsMembers(previousId) ||
        _selectionAddsMembers(requestId)) {
      _recomposeAndLayout();
    } else {
      _scene.rebuild(_rebuildGraphWithoutLayout);
    }
  }

  /// Whether selecting [beaconId] brings its members onto the field.
  bool _selectionAddsMembers(String? beaconId) =>
      beaconId != null &&
      (_requestWebsById.containsKey(beaconId) || _isPostId(beaconId));

  bool _isPostId(String beaconId) =>
      state.field?.posts.any((post) => post.id == beaconId) ?? false;

  /// Members of the selected Request or Post; only these become field holders,
  /// so a Post with many recipients shows them only while it is selected.
  List<ConstellationMemberWeb> get _selectedRequestWebs {
    final selectedId = state.selectedRequestId;
    if (selectedId == null) {
      return const [];
    }
    if (_isPostId(selectedId)) {
      return [
        for (final web in state.field!.memberWebs)
          if (web.beaconId == selectedId) web,
      ];
    }
    return _requestWebsById[selectedId] ?? const [];
  }

  Future<void> _fetchRequestWebs(String requestId) async {
    final case_ = _memberWebsCase;
    if (case_ == null ||
        _requestWebsById.containsKey(requestId) ||
        !_requestWebsInFlight.add(requestId) ||
        (state.field?.posts.any((post) => post.id == requestId) ?? false)) {
      return;
    }
    try {
      final webs = await case_.fetch(requestId);
      if (isClosed) {
        return;
      }
      _requestWebsById[requestId] = webs;
      if (state.selectedRequestId == requestId) {
        _recomposeAndLayout();
      }
    } on Object catch (e, st) {
      addError(e, st);
    } finally {
      _requestWebsInFlight.remove(requestId);
    }
  }

  void setViewMode(ConstellationViewMode viewMode) {
    if (isClosed || state.viewMode == viewMode) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(viewMode: viewMode));
  }

  void fitWholeField({required EdgeInsets insets}) {
    if (state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    _scene.fitWholeField(insets);
  }

  /// Selects [beaconId] (a Request or a Post) and centres the camera on its
  /// node when it is on the field. A beacon not on the field gets the usual
  /// «not available» notice from the selection listener.
  void focusBeacon(String beaconId, {required EdgeInsets insets}) {
    if (isClosed) {
      return;
    }
    selectRequest(beaconId);
    if (state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    _scene.centreOnBeacon(beaconId, insets);
  }

  void centerOnEgo({required EdgeInsets insets}) {
    if (state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    _scene.centreOnEgo(_viewer.id, insets);
  }

  void updateLabelBudgetContext({
    required Size viewport,
    required double textScaleFactor,
  }) {
    assert(
      textScaleFactor > 0 && textScaleFactor <= 4,
      'textScaleFactor is a dimensionless ratio, not a font size',
    );
    if (isClosed || viewport.isEmpty || !viewport.isFinite) {
      return;
    }
    _labelBudgetViewport = viewport;
    _labelBudgetTextScale = textScaleFactor;
    final next = constellationLabelBudget(
      viewport: viewport.lSize,
      textScaleFactor: textScaleFactor,
    );
    if (next == _appliedLabelBudget || state.field == null) {
      return;
    }
    if (state.hasPendingPlacementWrite || _interaction.draggingNodeId != null) {
      _labelBudgetRecomposePending = true;
      return;
    }
    _recomposeAndLayout();
  }

  void updateFootprintMetrics(ConstellationFootprintMetrics metrics) {
    if (isClosed || _footprintMetrics == metrics) {
      return;
    }
    _footprintMetrics = metrics;
    if (_scene.ephemeralOwnedLayoutAlgorithm != null ||
        _dispatchingLayoutRecovery) {
      return;
    }
    if (_scene.awaitingLayoutOutcome) {
      return;
    }
    _reconcileLayout(deferAutomaticReflow: true);
  }

  @visibleForTesting
  ConstellationFootprintMetrics? get footprintMetricsForTest =>
      _footprintMetrics;

  ConstellationLabelBudget _currentLabelBudget() {
    final budget = constellationLabelBudget(
      viewport: _labelBudgetViewport.lSize,
      textScaleFactor: _labelBudgetTextScale,
    );
    _appliedLabelBudget = budget;
    return budget;
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

  /// Re-lays out the nodes the user has not placed as a fresh plan, with no
  /// session inertia to stay close to. Anchored nodes keep their stored
  /// positions (the anchors, not prior hints, fix them); nothing is written.
  void rearrangeFreeNodes() {
    if (isClosed || state.composition == null) return;
    _forgetPriorHintNodeIds = {
      for (final node in graphController.nodes)
        tenturaLayoutDomainId(tenturaGraphNodeId(node)),
    };
    _reconcileLayout(immediateHandoff: true);
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
      footprints: layoutFootprints,
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
        FieldBeaconNode(request: final request?) =>
          ConstellationAnchorTarget.beacon(
            request.id,
          ),
        FieldBeaconNode(post: final post?) => ConstellationAnchorTarget.beacon(
          post.id,
        ),
        _ => null,
      };

  bool canDragNode(NodeDetails node) {
    return anchorTargetForNode(node) != null;
  }

  List<GraphNodeId> orderedNodeIdsForPaint() {
    return orderedNodesForPaint().map(tenturaGraphNodeId).toList();
  }

  List<NodeDetails> orderedNodesForPaint() => _scene.orderedNodesForPaint(
    anchors: [
      ...?state.composition?.anchorOverlay.anchors,
      ...?state.confirmedProjection?.anchors,
    ],
    activeTarget: state.activePlacementTarget,
    dragging:
        state.placementPhase == ConstellationPlacementPhase.draggingExisting ||
        state.placementPhase == ConstellationPlacementPhase.draggingNew,
  );

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
    _case.setMembershipFilters(filters);
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
    _case.setMembershipFilters(filters);
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
    _case.setMembershipFilters(defaultMembership);
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

  /// Checks the current content-wall-gated store snapshot. The server validates
  /// authorization when the action is submitted.
  Future<ConstellationRequestPreflight> preflightRequestAction(
    String beaconId,
  ) async {
    try {
      final field = _case.current.field;
      ConstellationRequest? refreshed;
      for (final request in field?.requests ?? const <ConstellationRequest>[]) {
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
      final ok = await _forwardCase.offerHelp(
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

  /// Body-only hit test for widget tests; production taps use [GraphView.nodeTapHitTester]
  /// and [resolveConstellationTap].
  NodeDetails? mapNodeAtSceneCentre(
    Offset sceneCentre, {
    bool peopleOnly = false,
  }) {
    final controller = graphController;
    if (!controller.canLayout) {
      return null;
    }
    final snapshot = controller.renderSnapshot;
    for (final graphId in orderedNodeIdsForPaint().reversed) {
      final point = snapshot.resolvePosition(graphId);
      final sceneNode = snapshot.topology.nodesById[graphId];
      if (point == null || sceneNode == null) {
        continue;
      }
      final rect = Rect.fromCenter(
        center: Offset(point.x, point.y),
        width: sceneNode.size.width,
        height: sceneNode.size.height,
      );
      if (rect.contains(sceneCentre)) {
        final payload = controller.nodePayloadForId(graphId);
        if (payload is NodeDetails &&
            (!peopleOnly || payload is FieldPersonNode)) {
          return payload;
        }
      }
    }
    return null;
  }

  void selectMapNode(NodeDetails node) {
    if (isClosed) {
      return;
    }
    switch (node) {
      case FieldPersonNode(:final person) when state.isComposing:
        if (person.id == viewerId) {
          return;
        }
        _toggleComposingPerson(person.id);
      case FieldPersonNode(:final person):
        if (person.id == viewerId) {
          return;
        }
        selectPerson(person.id);
      case FieldBeaconNode(request: final request?):
        selectRequest(request.id);
      case FieldBeaconNode(post: final post?):
        selectRequest(post.id);
      default:
        break;
    }
  }

  void _toggleComposingPerson(String personId) {
    _onComposingToggle?.call(personId);
  }

  /// Addressable people are a session-only overlay, never persisted in the field.
  ConstellationField _composerField(ConstellationField field) {
    if (!state.isComposing) return field;
    final projection = field.resolvedAnchorProjection;
    final peers = {
      for (final peer in field.peers)
        if (_composingCandidateIds.contains(peer.id)) peer.id: peer,
      for (final entry in _composerPeople.entries)
        if (_composingCandidateIds.contains(entry.key)) entry.key: entry.value,
    };
    return field.copyWith(
      peers: peers.values.toList(),
      requests: const [],
      posts: const [],
      memberWebs: const [],
      anchorProjection: ConstellationAnchorProjection(
        revision: projection.revision,
        anchors: [
          for (final anchor in projection.anchors)
            if (anchor.target.kind == ConstellationAnchorTargetKind.person &&
                _composingCandidateIds.contains(anchor.target.id))
              anchor,
        ],
        pinnedPeers: [
          for (final peer in projection.pinnedPeers)
            if (_composingCandidateIds.contains(peer.id)) peer,
        ],
        pinnedRequests: const [],
        supportPeers: const [],
        supportEdges: const [],
        serverFilteredBeaconIds: const [],
        serverFilteredBeaconCount: 0,
      ),
    );
  }

  void selectMapNodeAtSceneCentre(Offset sceneCentre) {
    final node = mapNodeAtSceneCentre(sceneCentre);
    if (node != null) {
      selectMapNode(node);
    }
  }

  void selectPerson(String? personId) {
    if (isClosed) {
      return;
    }
    final previousRequestId = state.selectedRequestId;
    final previousMemberId = _selectedRequestMemberId;
    // Keep a selected member after clearing the Request that brought them in.
    _selectedRequestMemberId =
        personId != null &&
            (personId == previousMemberId ||
                _selectedRequestWebs.any((web) => web.personId == personId))
        ? personId
        : null;
    emit(
      state.copyWith(
        selectedPersonId: personId,
        selectedRequestId: personId != null ? null : state.selectedRequestId,
      ),
    );
    if (previousMemberId != _selectedRequestMemberId ||
        (state.selectedRequestId != previousRequestId &&
            _selectionAddsMembers(previousRequestId))) {
      _recomposeAndLayout();
    } else {
      _scene.rebuild(_rebuildGraphWithoutLayout);
    }
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

  bool isPostId(String id) => postById(id) != null;

  ConstellationPost? postById(String id) {
    for (final post in state.field?.posts ?? const <ConstellationPost>[]) {
      if (post.id == id) return post;
    }
    return null;
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
    final overlay = state.composition?.anchorOverlay;
    if (overlay != null) {
      for (final request in overlay.pinnedRequests) {
        if (request.id == requestId) {
          return request;
        }
      }
    }
    final projection = field.anchorProjection;
    if (projection != null) {
      for (final request in projection.pinnedRequests) {
        if (request.id == requestId) {
          return request;
        }
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

    final budget = _currentLabelBudget();
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
    final composition = kReleaseMode
        ? _composePresentation(
            viewerId: _viewer.id,
            field: _composerField(field),
            localFilters: state.filters,
            asOfUtc: state.loadedAt ?? field.loadedAt,
            labelBudget: _currentLabelBudget(),
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _selectedRequestWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(field),
              localFilters: state.filters,
              asOfUtc: state.loadedAt ?? field.loadedAt,
              labelBudget: _currentLabelBudget(),
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _selectedRequestWebs,
              extraKeptPeerIds: _extraKeptPeerIds,
            ),
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
      deferAutomaticReflow: state.hasPendingPlacementWrite,
    );
  }

  void _reconcileLayout({
    bool deferAutomaticReflow = false,
    bool immediateHandoff = false,
  }) {
    if (deferAutomaticReflow &&
        (state.hasPendingPlacementWrite ||
            _interaction.draggingNodeId != null)) {
      return;
    }
    _layoutReconciliationCount++;
    _immediateHandoff = immediateHandoff;
    _scene.rebuild(_buildGraphScene);
    _immediateHandoff = false;
  }

  bool _immediateHandoff = false;

  /// Selection only changes which edges are drawn; it never moves nodes.
  void _rebuildGraphWithoutLayout() => _buildGraphScene(layout: false);

  void _buildGraphScene({bool layout = true}) {
    final field = state.field == null ? null : _composerField(state.field!);
    final paths = state.paths;
    final composition = state.composition;
    if (field == null || paths == null) {
      _scene.clear();
      return;
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
    final built = _scene.buildGraphScene(
      viewer: _viewer,
      field: field,
      paths: paths,
      composition: composition,
      plan: plan,
      keptPeerIds: state.keptPeerIds,
      selectedPersonId: state.selectedPersonId,
      selectedRequestId: state.selectedRequestId,
      loadedAt: state.loadedAt,
      isComposing: state.isComposing,
      composingSelectedIds: _composingSelectedIds,
      requestWebsById: _requestWebsById,
      footprintMetrics: _footprintMetrics,
      profileFromPeer: _profileFromPeer,
    );
    final nodes = built.nodes;
    final previousNodeIds = built.previousNodeIds;
    emit(state.copyWith(graphRevision: state.graphRevision + 1));
    if (state.isComposing) {
      _scene.placeComposerNodes(
        nodes: nodes,
        previousNodeIds: previousNodeIds,
        viewerId: viewerId,
        placedPersonIds: _composerPlacedPersonIds,
        personPositions: _composerPersonPositions,
        movedPersonIds: _composerMovedPersonIds,
        heldPersonId: _composerDragGraphId,
        confirmedAnchors: state.hasPendingPlacementWrite
            ? null
            : state.confirmedProjection?.anchors ??
                  const <ConstellationAnchor>[],
        draftCentre: _composingDraftCentre,
      );
      return;
    }
    if (!layout) {
      return;
    }
    _scene.scheduleLayoutHandoff(
      isClosed: () => isClosed,
      algorithm: () => graphSceneLayoutAlgorithm,
      immediate: _immediateHandoff,
    );
  }

  // Explicit-trust ids touching the viewer, indexed once per loaded field.
  ConstellationField? _viewerEdgesSource;
  final _viewerTrustsIds = <String>{};
  final _trustsViewerIds = <String>{};

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
  /// still can't honestly be marked "explicit"; the panel's
  /// [GraphPersonContextCubit] swaps in the server profile on selection, which
  /// carries the real visibility flags.
  Profile _profileFromPeer(ConstellationPerson peer) {
    final field = state.field;
    if (!identical(field, _viewerEdgesSource)) {
      _viewerEdgesSource = field;
      _viewerTrustsIds.clear();
      _trustsViewerIds.clear();
      for (final e in field?.edges ?? const <ConstellationTrustEdgeEntity>[]) {
        if (e.tier != 1) continue;
        if (e.src == _viewer.id) _viewerTrustsIds.add(e.dst);
        if (e.dst == _viewer.id) _trustsViewerIds.add(e.src);
      }
    }
    final viewerTrustsSubject = _viewerTrustsIds.contains(peer.id);
    final subjectTrustsViewer = _trustsViewerIds.contains(peer.id);
    return Profile(
      id: peer.id,
      displayName: peer.displayName ?? '',
      handle: peer.handle ?? '',
      image: peer.image,
      myVote: viewerTrustsSubject ? 1 : 0,
      subjectExplicitlyTrustsViewer: subjectTrustsViewer,
    );
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
