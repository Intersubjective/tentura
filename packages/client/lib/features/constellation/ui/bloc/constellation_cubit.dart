import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/consts.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/lazy_write_notice.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
import 'package:tentura/ui/utils/post_expiry_clock.dart';
import '../utils/constellation_presentation_frame.dart';

import '../../domain/constellation_anchor_composition.dart';
import '../../domain/constellation_consts.dart';
import '../../domain/constellation_density.dart';
import '../../domain/constellation_filters.dart';
import '../../domain/constellation_gather.dart';
import '../../domain/constellation_layout.dart';
import '../../domain/constellation_drag_cluster.dart';
import '../../domain/constellation_pin_position.dart';
import '../../domain/constellation_rearrange_all.dart';
import '../../domain/constellation_tidy_action.dart';
import '../../domain/constellation_tidy_offset_layer.dart';
import '../../domain/entity/constellation_layout_snapshot.dart';
import '../../domain/entity/constellation_tag_magnet.dart';
import '../../domain/use_case/constellation_arrangement_history.dart';
import '../scene/constellation_arrangement_layout.dart';
import '../scene/constellation_magnet_layout.dart';
import '../scene/constellation_community_scene_layout.dart';
import '../../domain/constellation_people.dart';
import '../../domain/constellation_multi_selection.dart';
import '../../domain/constellation_mutual_trust.dart';
import '../../domain/constellation_shown_field.dart';
import '../../domain/constellation_tag_filter.dart';
import '../../domain/constellation_tag_view_scope.dart';
import '../../domain/layout/constellation_tag_view_layout.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_anchor_projection.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/entity/constellation_trust_chain_person.dart';
import '../util/layout_geometry_adapters.dart';
import '../../domain/use_case/constellation_member_webs_case.dart';
import '../../domain/use_case/constellation_mutual_trust_case.dart';
import '../../domain/use_case/constellation_trust_chain_case.dart';
import '../../domain/entity/placement_outbox.dart';
import '../../domain/placement_overlay.dart';
import '../../domain/use_case/constellation_anchor_case.dart';
import '../../domain/use_case/constellation_placement_case.dart';
import '../../domain/use_case/constellation_tag_magnet_case.dart';
import '../../domain/use_case/constellation_field_store_case.dart';
import '../../domain/use_case/constellation_visibility_case.dart';
import '../../../graph/domain/entity/edge_details.dart';
import '../../../graph/domain/entity/node_details.dart';
import '../../../graph/ui/utils/graph_scene_ids.dart';
import '../../../graph/ui/utils/tentura_layout_algorithms.dart';
import '../utils/constellation_graph_scene.dart';
import '../scene/constellation_interaction_controller.dart';
import '../scene/constellation_scene_controller.dart';
import '../scene/constellation_tag_view_field_layout.dart';
import '../util/constellation_perf.dart';
import 'constellation_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../scene/constellation_scene_controller.dart'
    show ConstellationEdgeKind, kConstellationLayoutMaxHops;
export 'constellation_state.dart';
export '../../domain/constellation_tag_view_scope.dart';

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
    this._visibilityCase,
    this._mutualTrustCase,
    this._trustChainCase,
    this._tagMagnetCase,
    Set<String> Function(String personId)? ownTagIdsOf,
    ForwardCase? forwardCase,
    bool loadOnCreate = true,
    this.fieldMembershipV2Enabled = kFieldMembershipV2Enabled,
    this.semanticZoomEnabled = kFieldSemanticZoomEnabled,
    ConstellationPresentationComposer? composePresentation,
    ConstellationSceneController? scene,
  }) : _scene = scene ?? ConstellationSceneController(),
       _case = case_,
       _viewer = viewer,
       _composePresentation =
           composePresentation ??
           constellationPresentationComposer(
             semanticZoomEnabled: semanticZoomEnabled,
             fieldMembershipV2Enabled: fieldMembershipV2Enabled,
           ),
       _forwardCaseOverride = forwardCase,
       _magnetTagsOf = ownTagIdsOf ?? _noTagViewOwnTags,
       super(const ConstellationState()) {
    _placementCase?.history.applyTidyOffsets = (offsets) async {
      if (isClosed) return;
      _tidyOffsets.replaceAll(offsets);
      _reconcileLayout(immediateHandoff: true);
    };
    _anchorLifecycleToken = _anchorCase?.activate(viewerAccountId: viewer.id);
    _storeLease = _case.lease();
    _storeSub = _case.changes.listen(_onStoreChanged);
    _placementSub = _placementCase?.changes.listen(_onPlacementChanged);
    _magnetHintSub = _tagMagnetCase?.changes.listen(
      (_) => unawaited(_loadTagMagnets()),
    );
    // ignore: invalid_use_of_visible_for_testing_member
    graphController.scene.addListener(_onGraphSceneLayoutOutcomeChanged);
    graphController.addListener(_onGraphControllerChanged);
    if (loadOnCreate) {
      unawaited(load());
    }
    unawaited(_restoreVisibility());
  }

  final ConstellationFieldStoreCase _case;

  /// Recomposes at Post deadlines and as the last hour runs out, so a Post
  /// leaves the Field and fades with no network event.
  PostExpiryClock? _expiry;
  bool _expiryTickHeld = false;
  final ConstellationAnchorCase? _anchorCase;
  final ConstellationPlacementCase? _placementCase;
  final ConstellationMemberWebsCase? _memberWebsCase;
  final ConstellationVisibilityCase? _visibilityCase;
  final ConstellationMutualTrustCase? _mutualTrustCase;
  final ConstellationTrustChainCase? _trustChainCase;
  final ConstellationTagMagnetCase? _tagMagnetCase;
  final Profile _viewer;

  /// Draws the presence of bond and temporary people (`kFieldMembershipV2Enabled`).
  final bool fieldMembershipV2Enabled;

  /// Overview community geometry (`kFieldSemanticZoomEnabled`).
  final bool semanticZoomEnabled;
  final _communityLayouts = ConstellationCommunitySceneLayouts();

  /// Staging of the overview bulk move by community, for the graph view.
  Map<String, LayoutTransitionStage> get layoutTransitionStages =>
      _communityLayouts.transitionStages;
  bool _overviewLayout = false;

  /// The screen's zoom-level owner selects geometry as well as presentation.
  void setOverviewLayout(bool overview) {
    if (_overviewLayout == overview) return;
    _overviewLayout = overview;
    if (semanticZoomEnabled && !state.isComposing && state.tagView == null) {
      _scene.awaitingLayoutOutcome = true;
    }
  }

  /// Lazily fetched member webs per selected Request id (kept for the
  /// cubit's lifetime; a field reload does not invalidate it).
  final Map<String, List<ConstellationMemberWeb>> _requestWebsById = {};
  final Set<String> _requestWebsInFlight = {};

  /// Who each selected person trusts both ways, as the server answered it,
  /// with the [_trustGeneration] it was asked under (kept for the cubit's
  /// lifetime and asked again once the field's trust edges change).
  final Map<String, ({int generation, Set<String> ids})> _mutualTrustById = {};
  final Set<String> _mutualTrustInFlight = {};
  bool _mutualTrustRedrawPending = false;
  ConstellationField? _trustGenerationField;
  int _trustGenerationValue = 0;

  /// Bumped whenever trust on the field may have changed: a new read (its
  /// `loadedAt`) or other trust edges (a patch to the viewer's own trust).
  /// Anchor and placement changes copy the field but keep both, so they never
  /// ask the server again.
  int get _trustGeneration {
    final field = state.field;
    final previous = _trustGenerationField;
    if (!identical(field, previous)) {
      _trustGenerationField = field;
      if (previous == null ||
          field == null ||
          previous.loadedAt != field.loadedAt ||
          !listEquals(previous.edges, field.edges)) {
        _trustGenerationValue++;
      }
    }
    return _trustGenerationValue;
  }

  ({Set<String> local, Set<String> fetched, Set<String> ids})? _mutualTrustMemo;

  /// The chain the server named for each person the field shows no chain to,
  /// viewer first (kept for the cubit's lifetime; empty when the server had
  /// none or failed, so the person is not asked again).
  final Map<String, List<ConstellationTrustChainPerson>> _serverTrustChains =
      {};
  final Set<String> _serverTrustChainInFlight = {};
  final ForwardCase? _forwardCaseOverride;

  late final StoreLease _storeLease;
  StreamSubscription<ConstellationFieldStoreState>? _storeSub;
  StreamSubscription<PlacementOutboxState>? _placementSub;
  StreamSubscription<void>? _magnetHintSub;

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
  bool _footprintMetricsPending = false;

  @visibleForTesting
  double get labelBudgetTextScaleForTest => _labelBudgetTextScale;

  @visibleForTesting
  int get layoutReconciliationCount => _layoutReconciliationCount;

  /// How many times the pin layout input was built (one per composition,
  /// shared by every Pin button).
  int get pinLayoutInputBuildCount => _pinLayoutInputBuildCount;

  /// How many times the Text view builder ran (a view hidden behind the map
  /// must not rebuild).
  int get textViewBuildCount => _textViewBuildCount;

  void noteTextViewBuild() => _textViewBuildCount++;

  int _pinLayoutInputBuildCount = 0;
  int _textViewBuildCount = 0;
  Object? _pinLayoutInputComposition;
  ConstellationPlacedLayoutInput? _pinLayoutInput;
  ConstellationLayout? _pinBaseLayout;
  final _pinAvailability = <ConstellationAnchorTarget, bool>{};

  @visibleForTesting
  Set<String> get forgetPriorHintNodeIdsForTest => _forgetPriorHintNodeIds;

  @visibleForTesting
  int get writeCount => _writeCount;

  SceneLayoutAlgorithm get graphSceneLayoutAlgorithm {
    final normal =
        _layoutPreviewAlgorithm ??
        _withTidyOffsets(
          _scene.layoutAlgorithm(
            graphRevision: state.graphRevision,
            viewerId: _viewer.id,
            statePaths: state.paths,
            stateKeptPeerIds: state.keptPeerIds,
            forgetPriorHintNodeIds: _forgetPriorHintNodeIds,
          ),
        );
    final field = state.field;
    if (!semanticZoomEnabled ||
        field == null ||
        state.isComposing ||
        state.tagView != null ||
        _layoutPreviewAlgorithm != null ||
        _scene.tagViewAlgorithm != null ||
        _scene.testSceneLayoutAlgorithmOverride != null ||
        _scene.ephemeralOwnedLayoutAlgorithm != null) {
      return _withMagnets(normal);
    }
    return _communityLayouts.select(
      normal: _withMagnets(normal),
      field: field,
      egoId: viewerId,
      anchors: _scene.layoutAnchorByNodeId,
      initialPositions:
          graphController.renderSnapshot.layout?.positions ?? const {},
      overview: _overviewLayout,
    );
  }

  final _tagMagnets = <String, Offset>{};
  Map<String, ScenePoint> _magnetBasePositions = const {};
  Set<String> Function(String) _magnetTagsOf;

  Map<String, Offset> get tagMagnets => Map.unmodifiable(_tagMagnets);

  /// Bumped by every read and write of the saved magnets, so a read that
  /// started before a change never overwrites it.
  int _magnetEpoch = 0;
  int _pendingMagnetWrites = 0;

  /// The account changed: the next applied Field reads the magnets again.
  bool _magnetsStale = false;

  void _putTagMagnet(String tagId, Offset position) {
    if (_tagMagnets.isEmpty) {
      _magnetBasePositions = {
        for (final node in graphController.nodes)
          node.graphNodeId: ?graphController.renderSnapshot.resolvePosition(
            node.graphNodeId,
          ),
      };
    }
    _tagMagnets[tagId] = position;
  }

  void _dropTagMagnet(String tagId) {
    _tagMagnets.remove(tagId);
    if (_tagMagnets.isEmpty) _magnetBasePositions = const {};
  }

  Future<void> _loadTagMagnets() async {
    final magnetCase = _tagMagnetCase;
    if (magnetCase == null || isClosed) return;
    _magnetsStale = false;
    final epoch = ++_magnetEpoch;
    final List<ConstellationTagMagnet> saved;
    try {
      saved = await magnetCase.list();
    } on Object {
      // The magnets already shown stay; the next hint or load reads again.
      return;
    }
    if (isClosed || epoch != _magnetEpoch || _pendingMagnetWrites > 0) return;
    final loaded = {
      for (final magnet in saved)
        magnet.tagId: constellationV1AnchorToPoint(
          ConstellationAnchorPosition(
            xUnits: magnet.xUnits,
            yUnits: magnet.yUnits,
            coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
          ),
        ),
    };
    final unchanged =
        loaded.length == _tagMagnets.length &&
        loaded.entries.every((e) {
          final shown = _tagMagnets[e.key];
          return shown != null &&
              shown.dx == e.value.x &&
              shown.dy == e.value.y;
        });
    if (unchanged) return;
    for (final tagId in _tagMagnets.keys.toList()) {
      if (!loaded.containsKey(tagId)) _dropTagMagnet(tagId);
    }
    for (final entry in loaded.entries) {
      _putTagMagnet(entry.key, Offset(entry.value.x, entry.value.y));
    }
    _reconcileLayout(immediateHandoff: true);
  }

  /// Saves [position] for [tagId]; a failed save puts [previous] back.
  Future<void> _saveTagMagnet(
    String tagId,
    Offset position,
    Offset? previous,
  ) async {
    final magnetCase = _tagMagnetCase;
    if (magnetCase == null) return;
    final units = constellationPointToV1Anchor((
      x: position.dx,
      y: position.dy,
    ));
    _magnetEpoch++;
    _pendingMagnetWrites++;
    try {
      await magnetCase.save(
        tagId: tagId,
        xUnits: units.xUnits,
        yUnits: units.yUnits,
      );
    } on Object {
      if (!isClosed && _tagMagnets[tagId] == position) {
        if (previous == null) {
          _dropTagMagnet(tagId);
        } else {
          _putTagMagnet(tagId, previous);
        }
        _reconcileLayout(immediateHandoff: true);
      }
    } finally {
      _pendingMagnetWrites--;
      _magnetEpoch++;
    }
  }

  /// Deletes the saved magnet of [tagId]; a failed delete puts [previous] back.
  Future<void> _deleteTagMagnet(String tagId, Offset previous) async {
    final magnetCase = _tagMagnetCase;
    if (magnetCase == null) return;
    _magnetEpoch++;
    _pendingMagnetWrites++;
    try {
      await magnetCase.remove(tagId);
    } on Object {
      if (!isClosed && !_tagMagnets.containsKey(tagId)) {
        _putTagMagnet(tagId, previous);
        _reconcileLayout(immediateHandoff: true);
      }
    } finally {
      _pendingMagnetWrites--;
      _magnetEpoch++;
    }
  }

  void placeTagMagnet({
    required String tagId,
    required Offset position,
    required Set<String> Function(String) tagsOfPerson,
  }) {
    if (isClosed || state.tagView != null || state.isComposing) return;
    final previous = _tagMagnets[tagId];
    _magnetTagsOf = tagsOfPerson;
    _putTagMagnet(tagId, position);
    _reconcileLayout(immediateHandoff: true);
    unawaited(_saveTagMagnet(tagId, position, previous));
  }

  void removeTagMagnet(String tagId) {
    if (isClosed || state.tagView != null || !_tagMagnets.containsKey(tagId)) {
      return;
    }
    final previous = _tagMagnets[tagId]!;
    _dropTagMagnet(tagId);
    _reconcileLayout(immediateHandoff: true);
    unawaited(_deleteTagMagnet(tagId, previous));
  }

  void refreshTagMagnets(Set<String> availableTagIds) {
    if (isClosed || _tagMagnets.isEmpty) return;
    _tagMagnets.removeWhere((id, _) => !availableTagIds.contains(id));
    if (_tagMagnets.isEmpty) _magnetBasePositions = const {};
    _reconcileLayout(immediateHandoff: true);
  }

  SceneLayoutAlgorithm _withMagnets(SceneLayoutAlgorithm base) {
    final field = state.field;
    if (_tagMagnets.isEmpty ||
        field == null ||
        state.tagView != null ||
        state.isComposing ||
        _scene.tagViewAlgorithm != null ||
        _layoutPreviewAlgorithm != null) {
      return base;
    }
    return ConstellationMagnetLayout(
      base: base,
      priors: _magnetBasePositions,
      magnetsByPerson: {
        for (final person in field.peers)
          if (!isAnchored(ConstellationAnchorTarget.person(person.id)))
            'fp:${person.id}': [
              for (final tagId in _magnetTagsOf(person.id))
                if (_tagMagnets[tagId] case final at?) (x: at.dx, y: at.dy),
            ],
      },
      followers: {
        for (final r in field.requests)
          if (!isAnchored(ConstellationAnchorTarget.beacon(r.id)))
            'fr:${r.id}': 'fp:${r.authorId}',
        for (final p in field.posts)
          if (!isAnchored(ConstellationAnchorTarget.beacon(p.id)))
            'fr:${p.id}': 'fp:${p.authorId}',
      },
    );
  }

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
    _cancelPersonFocus();
    _expiry?.dispose();
    _storeLease.dispose();
    // Not awaited: the store's broadcast stream has no cancel cleanup, so the
    // returned future is the shared root-zone null future. Awaiting it would
    // hop the rest of close() out of the caller's zone (fake-async widget
    // tests then never deliver the state stream's done event).
    unawaited(_storeSub?.cancel());
    _storeSub = null;
    unawaited(_placementSub?.cancel());
    _placementSub = null;
    unawaited(_magnetHintSub?.cancel());
    _magnetHintSub = null;
    _clearClusterPresentations();
    _finishDropReflowSpans();
    // ignore: invalid_use_of_visible_for_testing_member
    graphController.scene.removeListener(_onGraphSceneLayoutOutcomeChanged);
    graphController.removeListener(_onGraphControllerChanged);
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
      _armExpiry(field);
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
    if (outcome is! GraphLayoutOutcomeSucceeded) {
      _pendingOverflowRefit = null;
    }

    if (!kReleaseMode &&
        (outcome is GraphLayoutOutcomeSucceeded ||
            outcome is GraphLayoutOutcomeFailed)) {
      _finishDropReflowSpans();
    }
    if (outcome is GraphLayoutOutcomeSucceeded) {
      _runPendingOverflowRefit();
      if (_footprintMetricsPending) {
        // Scene notifications cannot rebuild topology reentrantly.
        scheduleMicrotask(() {
          if (isClosed ||
              !_footprintMetricsPending ||
              _scene.awaitingLayoutOutcome) {
            return;
          }
          // Let the view reuse this request when it adopts the new algorithm.
          _reconcileLayout(
            deferAutomaticReflow: true,
            immediateHandoff: true,
          );
        });
      }
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
    unawaited(_loadTagMagnets());
  }

  void _armExpiry(ConstellationField field) {
    final deadlines = {
      for (final post in field.posts)
        if (post.expiresAt != null) post.expiresAt!,
    };
    // Created with the first deadline: a Field with no expiring Post has no
    // use for the clock or its app lifecycle listener.
    final expiry = deadlines.isEmpty
        ? _expiry
        : _expiry ??= PostExpiryClock(
            onTick: _onExpiryTick,
            clock: _case.nowUtc,
          );
    expiry?.setDeadlines(deadlines);
  }

  void _onExpiryTick() {
    if (isClosed || state.field == null) return;
    if (_scene.isFrozen) {
      _expiryTickHeld = true;
      return;
    }
    _recomposeForExpiry();
  }

  /// Moves the time the shown field's holders are judged at, then composes.
  void _recomposeForExpiry() {
    _shownAsOfUtc = _case.nowUtc();
    _recomposeAndLayout();
  }

  void _applyLoadedField(ConstellationField field) {
    _lastAppliedStoreField = field;
    _armExpiry(field);
    _shownAsOfUtc = _case.nowUtc();
    if (_magnetsStale) unawaited(_loadTagMagnets());
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
            asOfUtc: _case.nowUtc(),
            labelBudget: labelBudget,
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _holderWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(presentationField),
              localFilters: state.filters,
              asOfUtc: _case.nowUtc(),
              labelBudget: labelBudget,
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _holderWebs,
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
      asOfUtc: _case.nowUtc(),
      labelBudget: _currentLabelBudget(),
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
      selectedRequestWebs: _holderWebs,
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
    _cancelPersonFocus();
    _communityLayouts.clear();
    _tagMagnets.clear();
    _magnetBasePositions = const {};
    _magnetTagsOf = _noTagViewOwnTags;
    _magnetEpoch++;
    _magnetsStale = _tagMagnetCase != null;
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

  /// Starts dragging [target]. The [group] nodes (the rest of a selection
  /// the grabbed node is part of) move with it as one rigid group and are
  /// written with it on the drop; those that cannot be dragged stay put.
  void beginDragExisting({
    required ConstellationAnchorTarget target,
    Iterable<ConstellationAnchorTarget> group = const [],
  }) {
    if (isClosed) {
      return;
    }
    _interaction.beginDragging(target.graphNodeId);
    _beginClusterDragPresentation(target, group: group);
    graphController.setCameraInteractionGated(true);
    emit(
      state.copyWith(
        placementPhase: ConstellationPlacementPhase.draggingExisting,
        activePlacementTarget: target,
        placementFailureMessage: null,
      ),
    );
  }

  /// Starts dragging [target], which has no stored position yet; [group]
  /// as in [beginDragExisting].
  void beginDragNew({
    required ConstellationAnchorTarget target,
    Iterable<ConstellationAnchorTarget> group = const [],
  }) {
    if (isClosed) {
      return;
    }
    _interaction.beginDragging(target.graphNodeId);
    _beginClusterDragPresentation(target, group: group);
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
    _cancelPersonFocus();
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

  void _beginClusterDragPresentation(
    ConstellationAnchorTarget target, {
    Iterable<ConstellationAnchorTarget> group = const [],
  }) => _interaction.beginClusterDragPresentation(
    target,
    field: state.field,
    composition: state.composition,
    fallbackAnchors: [
      ...?state.composition?.anchorOverlay.anchors,
      ...?state.confirmedProjection?.anchors,
    ],
    group: state.isComposing ? const [] : _draggableGroup(target, group),
  );

  /// The [group] nodes that a drag of their own could move: on the graph now,
  /// draggable, and not [grabbed] itself.
  List<ConstellationAnchorTarget> _draggableGroup(
    ConstellationAnchorTarget grabbed,
    Iterable<ConstellationAnchorTarget> group,
  ) => [
    for (final member in group)
      if (member != grabbed)
        if (graphController.nodePayloadForId(
              constellationGraphNodeIdForTarget(member),
            )
            case final NodeDetails node
            when canDragNode(node) && anchorTargetForNode(node) == member)
          member,
  ];

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
      // A group member is written wherever it was, pinned before or not,
      // as a drag of its own would; a person's Request only when pinned.
      final isGroupMember = _interaction.groupMemberGraphIds.contains(
        entry.key,
      );
      if (isGroupMember
          ? _isRevokedWhileHeld(entry.value)
          : !remotePinnedBeaconIds.contains(entry.value.id)) {
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
      // A member that started outside the stored-position envelope and could
      // not get back in is not written (it would fail the whole batch); it
      // returns to where it was.
      if (isGroupMember &&
          !constellationPointWithinEnvelope((x: centre.dx, y: centre.dy))) {
        droppedCompanionGraphIds.add(entry.key);
        continue;
      }
      final companionTarget = entry.value;
      companions.add((
        target: companionTarget,
        position: constellationPointToV1Anchor((x: centre.dx, y: centre.dy)),
      ));
    }
    for (final graphId in droppedCompanionGraphIds) {
      graphController.clearPresentationForNodeId(graphId);
      _interaction.removeFromCluster(graphId);
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
    if (_mutualTrustRedrawPending) {
      scheduleMicrotask(_drainMutualTrustRedraw);
    }
    final storeHeld = _storeInputHeld;
    final outboxHeld = _outboxInputHeld;
    _storeInputHeld = false;
    _outboxInputHeld = false;
    final expiryHeld = _expiryTickHeld;
    _expiryTickHeld = false;
    if (isClosed) return false;
    final field = _case.current.field;
    if (storeHeld &&
        field != null &&
        !identical(field, _lastAppliedStoreField)) {
      _applyLoadedField(field);
    } else if (outboxHeld || storeHeld) {
      _composeOutboxChange();
    } else if (expiryHeld) {
      _recomposeForExpiry();
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
    final node = graphController.nodePayloadForId(parentGraphId)!;
    final dropCentre = clampClusterDragPosition(node, sceneCentre);
    final limited = _interaction.limitedClusterDelta(
      parentGraphId,
      dropCentre,
    );
    if (limited == null) {
      return;
    }
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

  /// Unpins the pinned ones of [targets] as one batch and one undo step;
  /// false when none of them was pinned.
  bool unpinAnchors(Iterable<ConstellationAnchorTarget> targets) {
    final pinned = targets.where(isAnchored).toList();
    if (isClosed || _placementCase == null || pinned.isEmpty) return false;
    _writeCount++;
    _placementCase.unpinAll(pinned);
    return true;
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
    bool saveManualHistory = true,
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
    // A group drag may hold more nodes than one batch takes: the rest go as
    // further batches, each with its first node as the parent.
    final writes = [(target: target, position: position), ...companions];
    for (
      var start = 0;
      start < writes.length;
      start += kConstellationPlacementBatchCap
    ) {
      final batch = writes.sublist(
        start,
        math.min(start + kConstellationPlacementBatchCap, writes.length),
      );
      _placementCase.place(
        parent: batch.first.target,
        position: batch.first.position,
        companions: batch.sublist(1),
        saveManualHistory: saveManualHistory,
      );
    }
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
            asOfUtc: _case.nowUtc(),
            labelBudget: _currentLabelBudget(),
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _holderWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(mergedField),
              localFilters: state.filters,
              asOfUtc: _case.nowUtc(),
              labelBudget: _currentLabelBudget(),
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _holderWebs,
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
    _cancelPersonFocus();
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
    if (requestId != null && requestById(requestId)?.isPlaceholder != true) {
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
    if (selectedId == null || requestById(selectedId)?.isPlaceholder == true) {
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

  /// [_selectedRequestWebs] plus the people whose Requests or Posts a
  /// show/hide switch hides while their degree stays shown (#645): composed
  /// as holders, so hiding content never takes a shown person off the field.
  /// Composition reads only `personId` from these.
  List<ConstellationMemberWeb> get _holderWebs {
    final field = state.field;
    if (field == null || state.isComposing || !hasHiddenLayers) {
      return _selectedRequestWebs;
    }
    _shownField(field);
    final hiddenHolders = _shownMemo.hiddenItemHolderIds;
    if (hiddenHolders.isEmpty) return _selectedRequestWebs;
    return [
      ..._selectedRequestWebs,
      for (final id in hiddenHolders)
        ConstellationMemberWeb(
          beaconId: '',
          personId: id,
          state: ConstellationMemberWebState.inside,
        ),
    ];
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

  /// Asks who the selected person trusts both ways, unless the answer held
  /// for them was read for the field's current trust edges. Once those
  /// change (a refresh, a patch to the viewer's own trust) the held answer is
  /// still drawn until the new one replaces it. An answer redraws the field only
  /// while that person is still the selected one, so a late answer for
  /// someone deselected (or replaced) changes nothing on screen.
  void _ensureMutualTrust() {
    final personId = state.selectedPersonId;
    final field = state.field;
    final case_ = _mutualTrustCase;
    if (case_ == null ||
        personId == null ||
        field == null ||
        state.isComposing) {
      return;
    }
    final generation = _trustGeneration;
    if (_mutualTrustById[personId]?.generation == generation ||
        !_mutualTrustInFlight.add(personId)) {
      return;
    }
    unawaited(_fetchMutualTrust(case_, personId, generation));
  }

  Future<void> _fetchMutualTrust(
    ConstellationMutualTrustCase case_,
    String personId,
    int generation,
  ) async {
    try {
      final ids = await case_.fetch(personId);
      if (isClosed) {
        return;
      }
      _mutualTrustById[personId] = (
        generation: generation,
        ids: Set.unmodifiable(ids),
      );
    } on Object catch (e, st) {
      if (isClosed) {
        return;
      }
      // Keep what was known; ask again only once the trust edges change.
      _mutualTrustById[personId] = (
        generation: generation,
        ids: _mutualTrustById[personId]?.ids ?? const {},
      );
      addError(e, st);
      return;
    } finally {
      _mutualTrustInFlight.remove(personId);
    }
    if (state.selectedPersonId == personId) {
      // An answer for older trust edges asks again at once.
      _ensureMutualTrust();
      _mutualTrustRedrawPending = true;
      _drainMutualTrustRedraw();
    }
  }

  /// Asks the server for the selected person's chain when the field shows
  /// none, once per person. An answer for someone deselected is only kept; the
  /// scene is redrawn only while that person is still the selected one.
  void _ensureServerTrustChain() {
    final personId = state.selectedPersonId;
    final case_ = _trustChainCase;
    if (case_ == null ||
        personId == null ||
        _serverTrustChains.containsKey(personId) ||
        _localTrustChain is! ConstellationTrustChainNone ||
        !_serverTrustChainInFlight.add(personId)) {
      return;
    }
    unawaited(_fetchServerTrustChain(case_, personId));
  }

  Future<void> _fetchServerTrustChain(
    ConstellationTrustChainCase case_,
    String personId,
  ) async {
    try {
      final chain = await case_.fetch(personId);
      if (isClosed) {
        return;
      }
      _serverTrustChains[personId] = List.unmodifiable(
        chain.length >= 2 &&
                chain.first.id == _viewer.id &&
                chain.last.id == personId
            ? chain
            : const <ConstellationTrustChainPerson>[],
      );
    } on Object catch (e, st) {
      if (isClosed) {
        return;
      }
      // Keep what the field shows; never ask again for this person.
      _serverTrustChains[personId] = const [];
      addError(e, st);
      return;
    } finally {
      _serverTrustChainInFlight.remove(personId);
    }
    if (state.selectedPersonId == personId &&
        _serverTrustChains[personId]!.isNotEmpty) {
      _mutualTrustRedrawPending = true;
      _drainMutualTrustRedraw();
    }
  }

  /// Draws an answer that arrived after its selection was drawn. Adding
  /// edges changes the scene topology, which would cancel a layout in flight
  /// or stop its transition, so the redraw waits for the scene to settle
  /// (and for a drag to end); [_onGraphControllerChanged] and
  /// [_releaseFreeze] retry it.
  void _drainMutualTrustRedraw() {
    if (!_mutualTrustRedrawPending ||
        isClosed ||
        _scene.isFrozen ||
        graphController.isLayoutSettling) {
      return;
    }
    _mutualTrustRedrawPending = false;
    _scene.rebuild(_rebuildGraphWithoutLayout);
  }

  void _onGraphControllerChanged() {
    if (_mutualTrustRedrawPending) {
      // Never change the topology from inside the controller's notification.
      scheduleMicrotask(_drainMutualTrustRedraw);
    }
  }

  /// Who the selected person trusts both ways (explicit trust marks only):
  /// what the field's own edges show at once, plus what the server answered
  /// for them. Empty with nobody selected, or while composing.
  Set<String> get selectedMutualTrustIds {
    final personId = state.selectedPersonId;
    final field = state.field;
    if (personId == null || field == null || state.isComposing) {
      return const {};
    }
    final local = constellationFieldMutualTrustIds(
      field: field,
      personId: personId,
    );
    final fetched = _mutualTrustById[personId]?.ids;
    if (fetched == null || fetched.isEmpty) {
      return local;
    }
    final memo = _mutualTrustMemo;
    if (memo != null &&
        identical(memo.local, local) &&
        identical(memo.fetched, fetched)) {
      return memo.ids;
    }
    final ids = Set<String>.unmodifiable({...local, ...fetched});
    _mutualTrustMemo = (local: local, fetched: fetched, ids: ids);
    return ids;
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

  /// The camera pan (no zoom) that keeps [node] clear of [insets], e.g.
  /// beside the preview sheet or person panel (#458); null when no pan is
  /// needed. The caller animates it through [panCameraTo].
  ({Offset from, Offset to})? revealPanFor(
    NodeDetails node, {
    required EdgeInsets insets,
  }) {
    if (isClosed || state.placementPhase != ConstellationPlacementPhase.idle) {
      return null;
    }
    return _scene.revealPan(tenturaGraphNodeId(node), insets);
  }

  /// Centres the viewport on [sceneCentre] at the current zoom.
  void panCameraTo(Offset sceneCentre) {
    if (isClosed) {
      return;
    }
    _scene.panCameraTo(sceneCentre);
  }

  void centerOnEgo({required EdgeInsets insets}) {
    if (state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    // Recenter is an instant camera jump to close detail. Restore its cached
    // geometry in the same turn, before labels are placed at the new scale.
    if (_overviewLayout &&
        semanticZoomEnabled &&
        !state.isComposing &&
        state.tagView == null) {
      final positions = _communityLayouts.normalPositions;
      if (positions != null) {
        graphController.animateTo(positions, animate: false);
      }
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
      _footprintMetricsPending = true;
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
    if (anchors.any((anchor) => anchor.target == target)) return true;
    // The people-only composing scene strips Request anchors from the
    // composition, but a pinned Request stays pinned (and unpinnable).
    return state.isComposing &&
        target.kind == ConstellationAnchorTargetKind.beacon &&
        (state.confirmedProjection?.anchors ?? const <ConstellationAnchor>[])
            .any((anchor) => anchor.target == target);
  }

  final _tidyOffsets = ConstellationTidyOffsetLayer();
  final _tidyPriors = <String, ScenePoint>{};
  SceneLayoutAlgorithm? _layoutPreviewAlgorithm;
  Map<String, ScenePoint>? _positionsBeforeLayoutPreview;

  SceneLayoutAlgorithm _withTidyOffsets(SceneLayoutAlgorithm base) {
    final pinned = {
      for (final a
          in state.composition?.anchorOverlay.anchors ??
              <ConstellationAnchor>[])
        a.target.id,
    };
    _tidyOffsets.clear(pinned);
    if (_tidyOffsets.isEmpty || state.tagView != null) return base;
    return ConstellationOffsetLayout(
      base,
      {
        for (final e in _tidyOffsets.offsets.entries)
          'fp:${e.key}': ScenePoint(x: e.value.x, y: e.value.y),
      },
      {
        for (final id in _tidyOffsets.offsets.keys)
          'fp:$id': ?_tidyPriors['fp:$id'],
      },
    );
  }

  void _clearArrangementPriors() {
    _tidyOffsets.clearAll();
    _tidyPriors.clear();
    _layoutPriorHints = null;
    _scene.ephemeralOwnedLayoutAlgorithm = null;
    _forgetPriorHintNodeIds = {
      for (final node in graphController.nodes)
        tenturaLayoutDomainId(tenturaGraphNodeId(node)),
    };
  }

  Future<bool> _saveBulkHistory(String reason) async {
    final placement = _placementCase;
    if (placement == null) return false;
    if (!placement.recordAutomaticHistory) return true;
    try {
      await placement.history.saveSnapshotBeforeBulkAction(reason);
      return !isClosed;
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      return false;
    }
  }

  Future<List<ConstellationLayoutSnapshot>> listLayoutSnapshots() =>
      _placementCase?.listLayoutSnapshots() ?? Future.value(const []);

  Future<void> saveFavouriteLayout() async {
    try {
      await _placementCase?.saveFavourite();
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
    }
  }

  Future<bool> restoreFavouriteLayout() async {
    final favourite = (await listLayoutSnapshots())
        .where((s) => s.kind == 0)
        .firstOrNull;
    return favourite != null && await restoreLayout(favourite);
  }

  /// Previews use a separate layout algorithm; neither the store nor the
  /// confirmed anchor projection is changed.
  void previewLayout(ConstellationLayoutSnapshot snapshot) {
    final field = state.field;
    if (isClosed || field == null) return;
    _positionsBeforeLayoutPreview ??= {
      for (final id in graphController.renderSnapshot.topology.nodesById.keys)
        id: ?graphController.renderSnapshot.resolvePosition(id),
    };
    final old = field.resolvedAnchorProjection;
    final projection = ConstellationAnchorProjection(
      revision: old.revision,
      anchors: [
        for (final e in snapshot.anchors.entries)
          ConstellationAnchor(
            target: e.key,
            position: e.value,
            revision: old.revision,
            placedAt: snapshot.createdAt,
          ),
      ],
      pinnedPeers: old.pinnedPeers,
      pinnedRequests: old.pinnedRequests,
      supportPeers: old.supportPeers,
      supportEdges: old.supportEdges,
      serverFilteredBeaconIds: old.serverFilteredBeaconIds,
      serverFilteredBeaconCount: old.serverFilteredBeaconCount,
    );
    final composed = _composePresentation(
      viewerId: viewerId,
      field: field.copyWith(anchorProjection: projection),
      localFilters: state.filters,
      asOfUtc: _case.nowUtc(),
      labelBudget: _currentLabelBudget(),
      expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
      selectedRequestWebs: _holderWebs,
      extraKeptPeerIds: _extraKeptPeerIds,
    );
    emit(
      state.copyWith(
        composition: composed,
        paths: composed.paths,
        keptPeerIds: composed.keptPeerIds,
        capped: composed.renderBudgetCapped,
      ),
    );
    droppedHolderIds = composed.droppedHolderIds;
    _reconcileSelection(composed);
    _tidyOffsets.clearAll();
    _tidyPriors.clear();
    _layoutPriorHints = null;
    final input = layoutInputFromComposition(
      viewerId: viewerId,
      composition: composed,
      labelPlan: composed.labelPlan,
      nodeSizes: const {},
      spacing: 16,
      footprints: layoutFootprints,
    );
    _layoutPreviewAlgorithm = ConstellationSceneLayoutAlgorithm(
      egoId: viewerId,
      paths: composed.paths,
      keptPeerIds: composed.keptPeerIds,
      maxHops: input.maxHops,
      visibleRequestsByAuthor: input.satelliteRequestIdsByAuthor,
      egoOwnRequestIds: input.egoOwnRequestIds,
      pinnedPersonIds: {
        for (final target in snapshot.anchors.keys)
          if (target.kind == ConstellationAnchorTargetKind.person) target.id,
      },
      pinnedRequestIds: {
        for (final target in snapshot.anchors.keys)
          if (target.kind == ConstellationAnchorTargetKind.beacon) target.id,
      },
      supportPersonIds: input.supportPersonIds,
      anchorByNodeId: input.anchorByNodeId,
      footprints: input.footprints,
      forgetPriorHintNodeIds: {
        for (final node in graphController.nodes)
          tenturaLayoutDomainId(tenturaGraphNodeId(node)),
      },
    );
    _reconcileLayout(immediateHandoff: true);
  }

  void cancelLayoutPreview() {
    final positions = _positionsBeforeLayoutPreview;
    _layoutPreviewAlgorithm = null;
    _positionsBeforeLayoutPreview = null;
    if (isClosed || positions == null) return;
    final field = state.field;
    if (field != null) {
      final presentationField = _desiredField(field);
      _lastPresentationField = presentationField;
      final composition = _composePresentation(
        viewerId: viewerId,
        field: _composerField(presentationField),
        localFilters: state.filters,
        asOfUtc: _case.nowUtc(),
        labelBudget: _currentLabelBudget(),
        expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
        selectedRequestWebs: _holderWebs,
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
    }
    _scene.requestLayout(
      releaseOnTerminal: _scene.activePresentationReleaseTokens(),
      algorithm: ConstellationFixedLayout(positions),
    );
  }

  Future<bool> restoreLayout(ConstellationLayoutSnapshot snapshot) async {
    final placement = _placementCase;
    if (placement == null) return false;
    final restored = await placement.restoreLayoutSnapshot(snapshot.id);
    if (!restored || isClosed) return false;
    _positionsBeforeLayoutPreview = null;
    _layoutPreviewAlgorithm = null;
    _clearArrangementPriors();
    await _case.requestRefresh(ConstellationRefreshReason.load);
    if (isClosed) return false;
    _reconcileLayout(immediateHandoff: true);
    return true;
  }

  Future<int> tidyUp({Set<String>? selection}) async {
    final placement = _placementCase;
    if (placement == null || !await _saveBulkHistory('rebuild')) return 0;
    final snap = graphController.renderSnapshot;
    final ego = snap.resolvePosition('fp:$viewerId');
    if (ego == null) return 0;
    final nodes = [
      for (final e in snap.topology.nodesById.entries)
        if (graphController.nodePayloadForId(e.key)
            case final FieldPersonNode node)
          if (snap.resolvePosition(e.key) case final p?)
            (
              id: node.id,
              position: (x: p.x, y: p.y),
              radius: node.size / 2,
              labelSize: (w: e.value.size.width, h: e.value.size.height),
              pinned:
                  node.id == viewerId ||
                  isAnchored(ConstellationAnchorTarget.person(node.id)),
            ),
    ];
    for (final n in nodes) {
      _tidyPriors.putIfAbsent(
        'fp:${n.id}',
        () => ScenePoint(x: n.position.x, y: n.position.y),
      );
    }
    final result = ConstellationTidyAction(
      layer: _tidyOffsets,
      history: placement.history,
    ).tidy(ego: (x: ego.x, y: ego.y), nodes: nodes, selection: selection);
    if (result == null) return 0;
    _reconcileLayout(immediateHandoff: true);
    return result.movedCount;
  }

  bool gather(Set<ConstellationAnchorTarget> targets) {
    final positioned = {
      for (final t in targets)
        t: ?graphController.getPositionOrNullForId(
          constellationGraphNodeIdForTarget(t),
        ),
    };
    if (positioned.length < 2) return false;
    final spacing =
        graphController.renderSnapshot.topology.nodesById.values.fold<double>(
          0,
          (v, n) => math.max(v, n.size.width),
        ) +
        16;
    final byKey = {for (final t in positioned.keys) t.mapKey: t};
    final gathered = arrangeConstellationGather(
      members: [
        for (final MapEntry(key: target, value: at) in positioned.entries)
          (id: target.mapKey, position: at.lPoint),
      ],
      spacing: spacing,
    );
    return placeArrangement({
      for (final MapEntry(key: id, value: point) in gathered.entries)
        byKey[id]!: point.offset,
    });
  }

  /// Re-lays out the nodes the user has not placed as a fresh plan, with no
  /// session inertia to stay close to. Anchored nodes keep their stored
  /// positions (the anchors, not prior hints, fix them); nothing is written.
  Future<void> rearrangeFreeNodes() async {
    if (isClosed || state.composition == null) return;
    if (!await _saveBulkHistory('rebuild')) return;
    _clearArrangementPriors();
    _forgetPriorHintNodeIds = {
      for (final node in graphController.nodes)
        tenturaLayoutDomainId(tenturaGraphNodeId(node)),
    };
    _reconcileLayout(immediateHandoff: true);
  }

  /// «Rearrange everyone, including pinned»: works out a full re-layout that
  /// ignores pins and shows how many people it would move. Nothing is moved
  /// or written until [applyRearrangePreview]; [cancelRearrangePreview]
  /// leaves the Field as it was.
  void previewRearrangeAll() {
    final composition = state.composition;
    if (isClosed ||
        composition == null ||
        state.isComposing ||
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    final snapshot = graphController.renderSnapshot;
    final input = layoutInputFromComposition(
      viewerId: _viewer.id,
      composition: composition,
      labelPlan: composition.labelPlan,
      nodeSizes: {
        for (final MapEntry(:key, :value)
            in snapshot.topology.nodesById.entries)
          tenturaLayoutDomainId(key): (
            width: value.size.width,
            height: value.size.height,
          ),
      },
      spacing: 16,
      footprints: layoutFootprints,
    );
    final rearranged = computeConstellationRearrangeAll(input);
    var moving = 0;
    for (final id in {
      ...input.automaticKeptPeerIds,
      ...input.pinnedPersonIds,
      ...input.supportPersonIds,
    }) {
      final from = snapshot.resolvePosition(
        constellationGraphNodeIdForTarget(ConstellationAnchorTarget.person(id)),
      );
      final to = rearranged.layout.positions[id];
      if (id != _viewer.id &&
          from != null &&
          to != null &&
          math.sqrt(math.pow(to.x - from.x, 2) + math.pow(to.y - from.y, 2)) >
              0.5) {
        moving++;
      }
    }
    emit(
      state.copyWith(
        rearrangePreview: ConstellationRearrangePreview(
          movingCount: moving,
          pinnedWrites: {
            for (final anchor in composition.anchorOverlay.anchors)
              if (rearranged.pinned[anchor.target.graphNodeId]
                  case final point?)
                anchor.target: constellationPointToV1Anchor(point),
          },
        ),
      ),
    );
  }

  void cancelRearrangePreview() {
    if (isClosed || state.rearrangePreview == null) return;
    emit(state.copyWith(rearrangePreview: null));
  }

  /// Applies the previewed arrangement: saves the layout it replaces as a
  /// history snapshot, writes every pinned node's new place as one batch (one
  /// entry [undoArrangement] takes back) and lays the unpinned people out
  /// afresh. False when nothing was applied.
  Future<bool> applyRearrangePreview() async {
    final preview = state.rearrangePreview;
    final placement = _placementCase;
    if (isClosed || preview == null || placement == null) {
      return false;
    }
    emit(state.copyWith(rearrangePreview: null));
    final writes = [
      for (final MapEntry(key: target, value: position)
          in preview.pinnedWrites.entries)
        (target: target, position: position),
    ];

    _writeCount++;
    try {
      await placement.history.saveSnapshotBeforeBulkAction('rebuild');
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      return false;
    }
    if (isClosed) return false;
    _clearArrangementPriors();
    if (writes.isEmpty) {
      _reconcileLayout(immediateHandoff: true);
      return true;
    }
    _submitUpsert(
      target: writes.first.target,
      position: writes.first.position,
      companions: writes.sublist(1),
      saveManualHistory: false,
    );
    return true;
  }

  /// «Сбросить позиции» (#251): removes every user-placed position of the
  /// account, hidden and off-screen ones included; the moved nodes return to
  /// the automatic layout here and, through the anchor hint, on the account's
  /// other devices. False when the reset could not be confirmed.
  /// With [saveHistory] the server saves the cleared layout, so the reset is
  /// one entry [undoArrangement] takes back.
  Future<bool> resetAllPositions({bool saveHistory = false}) async {
    final placement = _placementCase;
    if (isClosed || placement == null) {
      return false;
    }
    _writeCount++;
    try {
      if (saveHistory) await placement.flushPendingPlacements();
      _clearArrangementPriors();
      await placement.resetAll(saveHistory: saveHistory);
      return true;
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      return false;
    }
  }

  bool get canUndoArrangement => _placementCase?.history.canUndo ?? false;

  bool get canRedoArrangement => _placementCase?.history.canRedo ?? false;

  /// Takes back the last drag, unpin or reset. False when there is nothing to
  /// undo or the server refused.
  Future<bool> undoArrangement() => _runHistory(redo: false);

  /// Applies the last undone arrangement action again.
  Future<bool> redoArrangement() => _runHistory(redo: true);

  Future<bool> _runHistory({required bool redo}) async {
    final placement = _placementCase;
    if (isClosed || placement == null) {
      return false;
    }
    _writeCount++;
    try {
      final entry = redo
          ? placement.history.nextRedo
          : placement.history.nextUndo;
      final result = await (redo ? placement.redo() : placement.undo());
      if (result && entry is SnapshotRestoreEntry && !isClosed) {
        _clearArrangementPriors();
        await load();
        _reconcileLayout(immediateHandoff: true);
      }
      return result;
    } on Object catch (error, stackTrace) {
      if (!isClosed) addError(error, stackTrace);
      return false;
    }
  }

  /// «Arrange in sector» (#644): stores [targets] (scene centres of people,
  /// Requests and Posts) as user placements. A target outside the
  /// stored-position envelope is placed at its edge instead, held to the
  /// bounds a drag holds a node to, so the server never refuses the batch.
  /// A moved person's pinned Requests and Posts that are not arranged
  /// themselves follow their author by the same delta, as on a drag (one that
  /// cannot get inside the envelope stays where it is); an arranged Request
  /// or Post goes to its own target. Everything goes to the outbox together,
  /// in batches of [kConstellationPlacementBatchCap] based on the anchor revision the user
  /// sees: a reset made after it rejects them, and «Сбросить позиции» undoes
  /// them. Nodes that cannot be dragged are left out. False when nothing
  /// was written.
  bool placeArrangement(Map<ConstellationAnchorTarget, Offset> targets) {
    final placement = _placementCase;
    if (isClosed ||
        placement == null ||
        state.isComposing ||
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return false;
    }
    final snapshot = graphController.renderSnapshot;
    Offset? drawnAt(ConstellationAnchorTarget target) {
      final point = snapshot.resolvePosition(
        constellationGraphNodeIdForTarget(target),
      );
      return point == null ? null : Offset(point.x, point.y);
    }

    bool draggable(ConstellationAnchorTarget target) {
      final node = graphController.nodePayloadForId(
        constellationGraphNodeIdForTarget(target),
      );
      return node is NodeDetails &&
          canDragNode(node) &&
          anchorTargetForNode(node) == target;
    }

    final arranged = {
      for (final MapEntry(key: target, value: centre) in targets.entries)
        if (draggable(target))
          target: constellationClampToDragBounds(centre.lPoint).offset,
    };
    if (arranged.isEmpty || arranged.length > kConstellationSectorMaxItems) {
      return false;
    }
    final companions = <ConstellationAnchorTarget, Offset>{};
    for (final MapEntry(key: target, value: centre) in arranged.entries) {
      if (target.kind != ConstellationAnchorTargetKind.person) continue;
      final from = drawnAt(target);
      if (from == null) continue;
      final delta = centre - from;
      for (final beaconId in _interaction.pinnedCompanionBeaconIds(
        authorId: target.id,
        field: state.field,
        composition: state.composition,
      )) {
        final companion = ConstellationAnchorTarget.beacon(beaconId);
        final start = drawnAt(companion);
        if (arranged.containsKey(companion) || start == null) continue;
        final rest = constellationCompanionPosition(
          companionStart: start.lPoint,
          parentDelta: delta.lPoint,
        );
        // One that started outside the envelope and could not get back in
        // would fail the whole batch: it stays where it is.
        if (!constellationPointWithinEnvelope(rest)) continue;
        companions[companion] = rest.offset;
      }
    }
    final writes = [
      for (final MapEntry(key: target, value: centre) in {
        ...arranged,
        ...companions,
      }.entries)
        (
          target: target,
          position: constellationPointToV1Anchor(centre.lPoint),
        ),
    ];
    if (writes.any(
      (write) =>
          ConstellationAnchorPosition.validate(
                xUnits: write.position.xUnits,
                yUnits: write.position.yUnits,
                coordinateSpaceVersion: write.position.coordinateSpaceVersion,
              )
              is! ConstellationAnchorPositionValid,
    )) {
      return false;
    }
    unawaited(() async {
      if (!await _saveBulkHistory('rebuild') || isClosed) return;
      _submitUpsert(
        target: writes.first.target,
        position: writes.first.position,
        companions: writes.sublist(1),
        saveManualHistory: false,
      );
    }());
    return true;
  }

  bool canPinTarget(ConstellationAnchorTarget target) {
    if (isAnchored(target)) {
      return true;
    }
    final composition = state.composition;
    if (composition == null) {
      return false;
    }
    if (_pinLayoutInput == null ||
        !identical(_pinLayoutInputComposition, composition)) {
      _pinLayoutInputBuildCount++;
      _pinLayoutInputComposition = composition;
      _pinBaseLayout = null;
      _pinAvailability.clear();
      _pinLayoutInput = layoutInputFromComposition(
        viewerId: _viewer.id,
        composition: composition,
        labelPlan: composition.labelPlan,
        nodeSizes: const {},
        spacing: 16,
        priorHints: _layoutPriorHints,
        footprints: layoutFootprints,
      );
    }
    final layoutInput = _pinLayoutInput!;
    return _pinAvailability[target] ??=
        computeConstellationPinPosition(
          target: target,
          layoutInput: layoutInput,
          placedLayout: _pinBaseLayout ??= computeConstellationPinBaseLayout(
            layoutInput,
          ),
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
    if (node is FieldBeaconNode && node.request?.isPlaceholder == true) {
      return false;
    }
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

  // What the field shows (#645) and the selected person's chain (#641).

  final _shownMemo = ConstellationShownFieldMemo();

  /// When the shown field's hidden-type holders were last judged for expiry:
  /// the latest field apply or expiry tick.
  DateTime? _shownAsOfUtc;

  ConstellationField _shownField(ConstellationField field) => _shownMemo.shown(
    field,
    viewerId: _viewer.id,
    visibility: state.visibility,
    asOfUtc: _shownAsOfUtc,
  );

  /// The loaded field as the show/hide toggles leave it (#645): what the map
  /// and the list are composed from.
  ConstellationField? get shownField {
    final field = state.field;
    return field == null ? null : _shownField(field);
  }

  /// Whether a show/hide toggle hides anything (#645).
  bool get hasHiddenLayers => !state.visibility.showsEverything;

  /// Shows or hides Requests, Posts, or people of a trust degree (#645), and
  /// keeps the choice for this viewer on this device.
  void setVisibility(ConstellationVisibility visibility) {
    if (isClosed || state.visibility == visibility) {
      return;
    }
    _cancelUnsentPlacement(write: false);
    emit(state.copyWith(visibility: visibility));
    _keepVisibility();
    _recomposeAndLayout();
  }

  Future<void> _restoreVisibility() async {
    final visibilityCase = _visibilityCase;
    if (visibilityCase == null) return;
    final stored = await visibilityCase.read(viewerId: _viewer.id);
    // A choice made while the store was read wins over the stored one.
    if (isClosed || _visibilityTouched || stored == state.visibility) return;
    emit(state.copyWith(visibility: stored));
    if (state.field != null) _recomposeAndLayout();
  }

  bool _visibilityTouched = false;

  void _keepVisibility() {
    _visibilityTouched = true;
    unawaited(
      _visibilityCase?.write(
        viewerId: _viewer.id,
        visibility: state.visibility,
      ),
    );
  }

  Object? _countsFor;
  ConstellationVisibilityCounts? _counts;

  /// How many Requests, Posts and people of each degree the field holds with
  /// everything shown (#645): the counts on the show/hide chips, so a hidden
  /// type still says how much it hides.
  ConstellationVisibilityCounts? get visibilityCounts {
    final field = _lastPresentationField ?? state.field;
    final composition = state.composition;
    if (field == null || composition == null) {
      return null;
    }
    // With something hidden, the counts depend on the field and the Request
    // filters (a filtered-out pinned Request drops its support path).
    final source = hasHiddenLayers ? (field, state.filters) : composition;
    if (_counts != null && _sameCountsSource(source)) {
      return _counts;
    }
    // With something hidden, the population is that of the field composed
    // with everything shown (once per field).
    final people = hasHiddenLayers
        ? _composePresentation(
            viewerId: _viewer.id,
            field: field,
            localFilters: state.filters,
            asOfUtc: _case.nowUtc(),
            labelBudget: _currentLabelBudget(),
          ).eligiblePersonIds
        : composition.eligiblePersonIds;
    _countsFor = source;
    return _counts = constellationVisibilityCounts(
      field: field,
      viewerId: _viewer.id,
      peopleOnField: people,
      asOfUtc: _case.nowUtc(),
    );
  }

  bool _sameCountsSource(Object source) {
    final previous = _countsFor;
    return switch ((previous, source)) {
      (
        (final ConstellationField f0, final ConstellationFilters c0),
        (final ConstellationField f1, final ConstellationFilters c1),
      ) =>
        identical(f0, f1) && c0 == c1,
      _ => identical(previous, source),
    };
  }

  /// How the selected person is reached from the viewer (#641), or null when
  /// no person is selected (or the field is not composed yet).
  ///
  /// When the field shows no chain, the one the server named (if any) stands
  /// in for it, unless it passes through people the switches hide.
  ConstellationTrustChain? get selectedTrustChain {
    final local = _localTrustChain;
    if (local is! ConstellationTrustChainNone) {
      return local;
    }
    final served = _serverTrustChains[state.selectedPersonId];
    if (served == null || served.length < 2) {
      return local;
    }
    // A chain through people the switches hide is not shown (#641): the
    // panel says some people are hidden instead, and nothing is drawn.
    if (state.visibility.hidesPeople &&
        !constellationServedChainShown(
          path: [for (final p in served) p.id],
          visibility: state.visibility,
          degrees: _shownMemo.degrees,
        )) {
      return local;
    }
    return served.length == 2
        ? const ConstellationTrustChainDirect()
        : ConstellationTrustChainFound([for (final p in served) p.id]);
  }

  /// The name the server gave [personId] on the selected person's chain, for
  /// people the field does not hold.
  String? serverTrustChainName(String personId) {
    final served = _serverTrustChains[state.selectedPersonId];
    if (served == null) {
      return null;
    }
    for (final person in served) {
      if (person.id == personId && person.displayName.trim().isNotEmpty) {
        return person.displayName.trim();
      }
    }
    return null;
  }

  /// The chain of visible trust edges the field itself shows.
  ConstellationTrustChain? get _localTrustChain {
    final personId = state.selectedPersonId;
    final field = shownField;
    final composition = state.composition;
    if (personId == null ||
        field == null ||
        composition == null ||
        state.isComposing) {
      return null;
    }
    return _shownMemo.chain(
      viewerId: _viewer.id,
      personId: personId,
      field: field,
      composition: composition,
    );
  }

  /// Whether [node] is off the selected person's highlighted trust chain
  /// (#641): everything is, except the chain's people, the people the
  /// selected person trusts both ways (their edges are drawn to them) and the
  /// selected person's own Requests and Posts.
  bool isDimmedByTrustChain(NodeDetails node) {
    final chain = selectedTrustChain;
    if (chain is! ConstellationTrustChainFound) {
      return false;
    }
    return switch (node) {
      FieldPersonNode(:final person) =>
        !chain.path.contains(person.id) &&
            !selectedMutualTrustIds.contains(person.id),
      FieldBeaconNode(:final userId) => userId != chain.path.last,
      _ => true,
    };
  }

  /// Expands or collapses [authorId]'s hidden request satellites. Expanding
  /// with [refitInsets] refits the camera once, after the new layout lands, to
  /// the author and the satellites it revealed (#459). Collapsing refits to
  /// the author at full scale, as Center view does.
  void toggleSatelliteOverflow(String authorId, {EdgeInsets? refitInsets}) {
    if (isClosed) {
      return;
    }
    final expanding = !expandedSatelliteAuthorIds.contains(authorId);
    if (expanding) {
      expandedSatelliteAuthorIds.add(authorId);
    } else {
      expandedSatelliteAuthorIds.remove(authorId);
    }
    if (state.hasPendingPlacementWrite) {
      return;
    }
    final idsBefore = graphController.renderSnapshot.topology.nodesById.keys
        .toSet();
    _recomposeAndLayout();
    if (refitInsets != null) {
      _pendingOverflowRefit = (
        authorId: authorId,
        idsBefore: idsBefore,
        insets: refitInsets,
        expanding: expanding,
      );
    }
  }

  /// Camera refit owed to the next successful layout after an overflow
  /// toggle; any other recompose drops it.
  ({
    String authorId,
    Set<GraphNodeId> idsBefore,
    EdgeInsets insets,
    bool expanding,
  })?
  _pendingOverflowRefit;

  void _runPendingOverflowRefit() {
    final refit = _pendingOverflowRefit;
    _pendingOverflowRefit = null;
    if (refit == null ||
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    final authorGraphId = constellationGraphNodeIdForDomain(refit.authorId);
    if (refit.expanding) {
      _scene.fitNodes(
        refit.insets,
        include: (graphId) =>
            graphId == authorGraphId || !refit.idsBefore.contains(graphId),
        // The overview shows no chips: never strand the expanded chip there.
        minScale: kConstellationDistrictDetailScale,
        // Content too large for that scale stays framed on the author, so its
        // chip lands mid-screen, clear of the corner controls.
        focus: authorGraphId,
      );
      return;
    }
    // A collapsed «+N more» chip is sure of a spot only at close detail:
    // centre on the author at full scale, as Center view does.
    _scene.centreOnPerson(refit.authorId, refit.insets, resetScale: true);
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
    if (!state.isComposing) return _shownField(field);
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
    _cancelPersonFocus();
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
    _ensureMutualTrust();
    _ensureServerTrustChain();
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
    for (final request in field.requests) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  /// The field's own record of [personId] (membership, temporary Request,
  /// bond contexts), or null when they are not on the field.
  ConstellationPerson? fieldPersonById(String personId) {
    final field = state.field;
    if (field == null) {
      return null;
    }
    final projection = field.resolvedAnchorProjection;
    for (final peers in [
      projection.pinnedPeers,
      field.peers,
      projection.supportPeers,
    ]) {
      for (final peer in peers) {
        if (peer.id == personId) {
          return peer;
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
    final projection = field.resolvedAnchorProjection;
    for (final peers in [
      projection.pinnedPeers,
      field.peers,
      projection.supportPeers,
    ]) {
      for (final peer in peers) {
        if (peer.id == personId) {
          return _profileFromPeer(peer);
        }
      }
    }
    return null;
  }

  ConstellationComposedPresentation? _peopleFor;
  List<ConstellationFieldPerson> _people = const [];

  /// The field's people, the same population the map draws (#253): the
  /// viewer first, then everyone else by name.
  List<ConstellationFieldPerson> get fieldPeople {
    final field = state.field;
    final composition = state.composition;
    if (field == null || composition == null) {
      return const [];
    }
    if (!identical(composition, _peopleFor)) {
      _peopleFor = composition;
      _people = constellationFieldPeople(
        field: field,
        composition: composition,
        viewerId: _viewer.id,
        viewerName: _viewer.shownName,
      );
    }
    return _people;
  }

  /// [personId]'s Posts that are on the field, latest activity first.
  List<ConstellationPost> postsForPerson(String personId) {
    final eligible = state.composition?.eligibleRequestIds ?? const {};
    return [
      for (final post in state.field?.posts ?? const <ConstellationPost>[])
        if (post.authorId == personId && eligible.contains(post.id)) post,
    ]..sort((a, b) {
      final byActivity = b.lastActivityAt.compareTo(a.lastActivityAt);
      return byActivity != 0 ? byActivity : a.id.compareTo(b.id);
    });
  }

  Timer? _personFocusTimer;

  void _cancelPersonFocus() {
    _personFocusTimer?.cancel();
    _personFocusTimer = null;
  }

  /// Selects [personId] for two seconds (highlighting the node and opening
  /// the person panel), and centres the camera, keeping the zoom (#253).
  /// An intentional selection takes over from the temporary search focus.
  void focusPerson(String personId, {required EdgeInsets insets}) {
    if (isClosed || personId == _viewer.id) {
      return;
    }
    selectPerson(personId);
    _personFocusTimer = Timer(const Duration(seconds: 2), () {
      _personFocusTimer = null;
      if (!isClosed && state.selectedPersonId == personId) {
        selectPerson(null);
      }
    });
    if (state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    _scene.centreOnPerson(personId, insets);
  }

  /// [personId]'s Requests on the field, pinned ones included (#673): a FULL
  /// read carries a pinned Request only in the anchor projection, so reading
  /// `requests` alone loses it after a reload.
  List<ConstellationRequest> discoverableRequestsForPerson(String personId) {
    final field = shownField;
    if (field == null) {
      return const [];
    }
    final byId =
        <String, ConstellationRequest>{
          for (final request in [
            ...field.requests,
            ...field.resolvedAnchorProjection.pinnedRequests,
          ])
            request.id: request,
        }..removeWhere(
          (_, request) => request.isPlaceholder || request.authorId != personId,
        );
    final filteredRequestIds = _filteredRequestIds(field, byId.values);
    return [
      for (final request in byId.values)
        if (filteredRequestIds.contains(request.id)) request,
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  Set<String> _filteredRequestIds(
    ConstellationField field, [
    Iterable<ConstellationRequest>? requests,
  ]) {
    final asOf = state.loadedAt ?? field.loadedAt;
    return filterRequestIds(
      requests: (requests ?? field.requests).map(
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
    _pendingOverflowRefit = null;
    final field = state.field;
    if (field == null) {
      return;
    }
    final composition = kReleaseMode
        ? _composePresentation(
            viewerId: _viewer.id,
            field: _composerField(field),
            localFilters: state.filters,
            asOfUtc: _case.nowUtc(),
            labelBudget: _currentLabelBudget(),
            expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
            selectedRequestWebs: _holderWebs,
            extraKeptPeerIds: _extraKeptPeerIds,
          )
        : ConstellationPerf.timeSync(
            'compose',
            () => _composePresentation(
              viewerId: _viewer.id,
              field: _composerField(field),
              localFilters: state.filters,
              asOfUtc: _case.nowUtc(),
              labelBudget: _currentLabelBudget(),
              expandedSatelliteAuthorIds: expandedSatelliteAuthorIds,
              selectedRequestWebs: _holderWebs,
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

  Set<String> Function(String personId) _tagViewOwnTagIdsOf = _noTagViewOwnTags;
  static Set<String> _noTagViewOwnTags(String personId) => const {};

  /// Where the Field had every node when the tag view opened.
  Map<GraphNodeId, Offset> _tagViewFieldPositions = const {};

  /// The scene is being rebuilt for the tag view (not by anything else).
  bool _tagViewBuilding = false;

  /// The tag view was just left and the Field has not been laid out since.
  bool _tagViewLeaving = false;

  /// The tag view is open, or the Field is still moving back from it.
  bool get tagViewMotionActive => state.tagView != null || _tagViewLeaving;

  /// Where the dots of the people the tag view shows as dots are drawn.
  Map<String, Offset> get tagViewDotPositions => {
    for (final id in state.tagView?.scope.dotIds ?? const <String>{})
      id: ?_tagViewFieldPositions['fp:$id'],
  };

  /// Opens the tag view of [filter]: a separate look at the people it matches.
  /// The Field's composition and anchors are left alone; nothing is written.
  void enterTagView({
    required ConstellationTagFilter filter,
    required Set<String> Function(String personId) ownTagIdsOf,
  }) {
    final field = state.field;
    if (isClosed || field == null || state.isComposing || filter.isEmpty) {
      return;
    }
    _tagViewOwnTagIdsOf = ownTagIdsOf;
    if (state.tagView == null) {
      _tagViewFieldPositions = {
        for (final id in graphController.renderSnapshot.topology.nodesById.keys)
          id: ?graphController.getPositionOrNullForId(id),
      };
    }
    _applyTagView(
      filter,
      state.tagView?.others ?? ConstellationTagViewOthers.dots,
    );
  }

  void setTagViewOthers(ConstellationTagViewOthers others) {
    final view = state.tagView;
    if (isClosed || view == null || view.others == others) return;
    _applyTagView(view.filter, others);
  }

  void exitTagView() {
    if (isClosed || state.tagView == null) return;
    // Back to exactly the places the Field had: the Field is not laid out
    // again, so nothing in it moves.
    _scene.tagViewAlgorithm = ConstellationTagViewFieldLayoutAlgorithm(
      egoGraphId: 'fp:${_viewer.id}',
      tagIds: const [],
      members: const [],
      fieldPositions: _tagViewFieldPositions,
      followers: const {},
    );
    _tagViewFieldPositions = const {};
    _tagViewLeaving = true;
    emit(state.copyWith(tagView: null));
    _reconcileTagView();
  }

  /// A person dragged in the tag view only follows the pointer; on release
  /// they return to their place and nothing is written.
  void endTagViewDrag(NodeDetails node) =>
      graphController.clearPresentationForNodeId(node.graphNodeId);

  void _applyTagView(
    ConstellationTagFilter filter,
    ConstellationTagViewOthers others,
  ) {
    final field = state.field!;
    final scope = resolveConstellationTagViewScope(
      filter: filter,
      people: field.peers,
      ownTagIdsOf: _tagViewOwnTagIdsOf,
      others: others,
    );
    final egoId = 'fp:${_viewer.id}';
    final ego = _tagViewFieldPositions[egoId];
    final tagIds = [
      ...filter.selectedOwn.toList()..sort(),
      ...[for (final kind in filter.selectedAuto) 'auto:${kind.name}']..sort(),
    ];
    final members = <TagViewPerson>[];
    for (final person in field.peers) {
      final base = _magnetBasePositions['fp:${person.id}'];
      final at = base == null
          ? _tagViewFieldPositions['fp:${person.id}']
          : Offset(base.x, base.y);
      if (at == null || !scope.memberIds.contains(person.id)) continue;
      final from = ego ?? at;
      final paths = state.paths;
      members.add((
        id: 'fp:${person.id}',
        angle: math.atan2(at.dy - from.dy, at.dx - from.dx),
        depth: paths == null || paths.ring.contains(person.id)
            ? kConstellationLayoutMaxHops + 1
            : paths.depth[person.id] ?? kConstellationLayoutMaxHops,
        tagIds: {
          for (final tagId in filter.selectedOwn)
            if (_tagViewOwnTagIdsOf(person.id).contains(tagId)) tagId,
          for (final kind in filter.selectedAuto)
            if (person.autoTagKinds.contains(kind)) 'auto:${kind.name}',
        },
      ));
    }
    final followers = <GraphNodeId, GraphNodeId>{};
    for (final id in _tagViewFieldPositions.keys) {
      final node = graphController.nodePayloadForId(id);
      if (node is FieldBeaconNode) followers[id] = 'fp:${node.userId}';
    }
    _scene.tagViewAlgorithm = ConstellationTagViewFieldLayoutAlgorithm(
      egoGraphId: egoId,
      tagIds: tagIds,
      members: members,
      fieldPositions: _tagViewFieldPositions,
      followers: followers,
    );
    emit(
      state.copyWith(
        tagView: ConstellationTagView(
          filter: filter,
          others: others,
          scope: scope,
        ),
      ),
    );
    _reconcileTagView();
  }

  void _reconcileTagView() {
    _tagViewBuilding = true;
    try {
      _reconcileLayout(immediateHandoff: true);
    } finally {
      _tagViewBuilding = false;
    }
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
    // The Field lays itself out again after anything but the tag view.
    if (!_tagViewBuilding && state.tagView == null) {
      _scene.tagViewAlgorithm = null;
      _tagViewLeaving = false;
    }
    // Every build draws the latest mutual trust answer, and asks for one when
    // the selected person has none for this field.
    _mutualTrustRedrawPending = false;
    _ensureMutualTrust();
    _ensureServerTrustChain();
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
    if (layout) _footprintMetricsPending = false;
    final built = _scene.buildGraphScene(
      viewer: _viewer,
      field: field,
      paths: paths,
      composition: composition,
      plan: plan,
      keptPeerIds: state.keptPeerIds,
      selectedPersonId: state.selectedPersonId,
      selectedRequestId: state.selectedRequestId,
      trustChain: selectedTrustChain,
      mutualTrustIds: selectedMutualTrustIds,
      asOfUtc: _case.nowUtc(),
      isComposing: state.isComposing,
      composingSelectedIds: _composingSelectedIds,
      requestWebsById: _requestWebsById,
      footprintMetrics: _footprintMetrics,
      profileFromPeer: _profileFromPeer,
      fieldMembershipV2Enabled: fieldMembershipV2Enabled,
      hiddenPersonIds: {
        ...?state.tagView?.scope.hiddenIds,
        ...?state.tagView?.scope.dotIds,
      },
    );
    final nodes = built.nodes;
    final previousNodeIds = built.previousNodeIds;
    if (!layout) {
      _scene.retainLayoutAlgorithmForNextRevision(state.graphRevision);
    }
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
            : composition?.anchorOverlay.anchors ??
                  state.confirmedProjection?.anchors ??
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
