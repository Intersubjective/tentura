import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/app/platform/web_semantics.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/scene/constellation_zoom_level_controller.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/widget/adaptive_context_overlay.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/people_tags/ui/widget/tag_editor_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/widget/undo_snack_bar.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/browser_context_menu_hold.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import '../../domain/constellation_consts.dart';
import '../../domain/constellation_trust_chain.dart';
import '../../domain/constellation_field_unread_glow.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_selection_cubit.dart';
import '../bloc/constellation_tag_lens_cubit.dart';
import '../../domain/constellation_forward_tree_marker.dart';
import '../util/constellation_perf.dart';
import '../utils/constellation_edge_style.dart';
import '../utils/constellation_graph_scene.dart';
import '../utils/constellation_presentation_frame.dart';
import '../utils/constellation_tap_resolver.dart';
import 'constellation_field_item_actions.dart';
import 'constellation_field_topo_backdrop.dart';
import '../../domain/entity/constellation_field_target_kind.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_camera_controls.dart';
import 'constellation_composer_radius.dart';
import 'constellation_composer_sheet.dart';
import 'constellation_create_entry.dart';
import 'constellation_filter_bar.dart';
import 'constellation_forward_tree_overlay_bar.dart';
import 'constellation_minimap.dart';
import 'constellation_no_contacts.dart';
import 'constellation_overflow_group.dart';
import 'constellation_person_field_items_section.dart';
import 'constellation_presence_halo_layer.dart';
import 'constellation_request_status_marker.dart';
import 'constellation_node_semantics.dart';
import 'constellation_request_label.dart';
import 'constellation_request_preview_sheet.dart';
import 'constellation_pin_placeholder_sheet.dart';
import 'constellation_field_preview_people_rows.dart';
import 'constellation_post_preview_sheet.dart';
import 'constellation_presence_line.dart';
import 'constellation_temporary_outline.dart';
import 'constellation_text_view.dart';
import 'constellation_trust_chain_line.dart';
import 'constellation_visibility_bar.dart';
import 'constellation_placement_marker_layer.dart';
import 'constellation_arranging_toolbar.dart';
import 'constellation_selection_layers.dart';
import 'constellation_tag_hull_layer.dart';
import 'constellation_tag_lens_panel.dart';
import 'constellation_tag_row.dart';
import 'constellation_tag_magnet_layer.dart';
import 'constellation_rearrange_preview_bar.dart';
import 'constellation_tag_view_header.dart';
import 'constellation_viewport_overlay.dart';

const _mapNodeSemanticsPrefix = 'constellation.mapNode:';

Widget _wrapFieldBeaconMapChrome(NodeDetails node, Widget child) {
  return switch (node) {
    FieldBeaconNode(request: final request?) when !request.isPlaceholder =>
      ConstellationFieldBeaconMapChrome(
        targetKind: ConstellationFieldTargetKind.request,
        beaconId: request.id,
        child: child,
      ),
    FieldBeaconNode(post: final post?) => ConstellationFieldBeaconMapChrome(
      targetKind: ConstellationFieldTargetKind.post,
      beaconId: post.id,
      child: child,
    ),
    _ => child,
  };
}

class _CancelPlacementIntent extends Intent {
  const _CancelPlacementIntent();
}

class _UndoArrangementIntent extends Intent {
  const _UndoArrangementIntent();
}

class _RedoArrangementIntent extends Intent {
  const _RedoArrangementIntent();
}

class ConstellationBody extends StatefulWidget {
  const ConstellationBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    this.presentationFrameHolder,
    this.onFieldContextSheetExpandedChanged,
    this.arrangeV2Enabled = kFieldArrangeV2Enabled,
    this.peopleTagsEnabled = kPeopleTagsEnabled,
    this.fieldMembershipV2Enabled = kFieldMembershipV2Enabled,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  /// The Arrange menu, Ctrl/Cmd+Z undo / redo and the nearest-ring caption
  /// while dragging (`kFieldArrangeV2Enabled`).
  final bool arrangeV2Enabled;

  /// With [arrangeV2Enabled], the tag lens panel offers the tag view
  /// (`kPeopleTagsEnabled`).
  final bool peopleTagsEnabled;

  /// A temporary person's dashed outline and the bond / temporary line in the
  /// person panel (`kFieldMembershipV2Enabled`).
  final bool fieldMembershipV2Enabled;

  /// When set (Field screen on compact widths), true while the map context
  /// sheet is on its expanded detent, not peek.
  final ValueChanged<bool>? onFieldContextSheetExpandedChanged;

  /// When set (tests only), the viewport overlay writes its frame here.
  final ConstellationPresentationFrameHolder? presentationFrameHolder;

  static const _canvasSize = GraphCanvasSize.fixed(
    Size(kConstellationCanvasExtent, kConstellationCanvasExtent),
  );

  @override
  State<ConstellationBody> createState() => _ConstellationBodyState();
}

class _ConstellationBodyState extends State<ConstellationBody>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _layoutTransitionDuration = Duration(milliseconds: 350);

  /// A Field ↔ tag view move takes 400–500 ms.
  static const _tagViewTransitionDuration = Duration(milliseconds: 450);

  static const _revealDuration = Duration(milliseconds: 280);
  static const _fieldSettleBackDelay = Duration(milliseconds: 150);

  Size? _lastLabelBudgetViewport;
  double? _lastLabelBudgetTextScale;
  (Brightness, Locale, double, int)? _lastFootprintSyncKey;
  SceneLayoutAlgorithm? _mountedLayoutAlgorithm;
  String? _selectionUnavailableMessage;
  final _internalFrameHolder = ConstellationPresentationFrameHolder();
  final _graphStackKey = GlobalKey();
  final _mapFocus = FocusNode(debugLabel: 'ConstellationMap');
  final _fieldTopChromeKey = GlobalKey();
  final _bottomChromeColumnKey = GlobalKey();
  double _fieldTopChromeHeight = 0;
  double _mapStackHeight = 0;

  /// Latest [LayoutBuilder] max height for the map stack; updated during
  /// layout so sheet detent math stays in sync when the scaffold app bar
  /// collapses (#974).
  double _layoutMapStackHeight = 0;
  double _compactSheetHeight = 0;
  bool _compactSheetDetentExpanded = false;
  bool _wasCompactPanelOpen = false;

  /// Measured height of the bottom Field chrome column (tag lens + arranging +
  /// selection). Used for FCP §C camera insets.
  double _bottomChromeColumnHeight = 0;

  double get _effectiveMapStackHeight =>
      _layoutMapStackHeight > 0 ? _layoutMapStackHeight : _mapStackHeight;

  /// Kept across builds: it remembers which marker is the map's Tab stop.
  final _mapTraversalPolicy = _ConstellationMapReadingOrderPolicy();

  // Where the pointer last was, to tell a drop on a tag chip from a pin.
  Offset? _lastPointerGlobal;
  String? _lastTagChipDropHint;
  StreamSubscription<void>? _magnetTagsSubscription;

  late final GraphController<NodeDetails, EdgeDetails> _graphController;
  // The screen's single zoom-level owner, shared with the viewport overlay.
  late final ConstellationZoomLevelController _zoom;
  ConstellationZoomLevelController? _ownZoom;
  // Outlives the minimap widget, which leaves at the close level.
  // FCP §C: compact surfaces start with the minimap collapsed; width is read
  // in didChangeDependencies (first pass) so MediaQuery is available before
  // the first build.
  final _minimapExpanded = ValueNotifier<bool>(false);
  bool _minimapExpandedInitialized = false;
  int _pointersDown = 0;

  ConstellationTagHullHitTester? _tagHullHitTester;

  // The own tag whose hull a press-and-hold lifted into a drag (#1021).
  String? _liftedTagId;

  /// Handle node for a hull drag the user started from the secondary menu
  /// (#1021): the area follows the pointer until the next primary click.
  GraphNodeId? _tagHullMenuDragNodeId;

  // The level held back near a threshold while a gesture ran must catch up
  // with the scale once the last pointer is gone.
  void _onPointerReleased() {
    // A pointer pressed on the map still reports its release along the hit
    // path recorded at press time, even when the map went away meanwhile;
    // a disposed body has no level left to catch up.
    if (!mounted) {
      return;
    }
    _pointersDown = math.max(0, _pointersDown - 1);
    if (_pointersDown == 0) {
      _zoom.update(_graphController.cameraScale, gestureActive: false);
      _rescheduleFieldSettleBack();
    }
  }

  void _updateTagHullHitTester(ConstellationCubit cubit) {
    final store = _peopleTags;
    final lensCubit = maybeConstellationTagLens(context);
    if (store == null || lensCubit == null) {
      _tagHullHitTester = null;
      return;
    }
    final fieldIds = {for (final person in cubit.fieldPeople) person.id};
    final tags = [
      for (final tag in store.tags)
        if (store.peopleInTag(tag.id).any(fieldIds.contains)) tag,
    ];
    _tagHullHitTester ??= ConstellationTagHullHitTester(
      hitsMapNode: (scenePoint) =>
          cubit.mapNodeAtSceneCentre(scenePoint) != null,
    );
    _tagHullHitTester!.update(
      controller: cubit.graphController,
      tags: tags,
      selectedTagIds: lensCubit.state.selectedOwn,
      peopleOf: store.peopleInTag,
    );
  }

  /// Lifts the own tag whose hull holds empty [scene] space: its people
  /// start a weighted group drag; returns the node the pointer carries.
  GraphNodeId? _liftTagHull(ConstellationCubit cubit, Offset scene) {
    final store = _peopleTags;
    if (store == null ||
        cubit.state.tagView != null ||
        cubit.state.isComposing) {
      return null;
    }
    _updateTagHullHitTester(cubit);
    final tagId = _tagHullHitTester?.tagHullAt(scene);
    if (tagId == null) {
      return null;
    }
    final handle = cubit.beginDragTagArea(
      tagId: tagId,
      peopleOfTag: store.peopleInTag,
      tagsOfPerson: store.tagsOfPerson,
    );
    if (handle == null) {
      return null;
    }
    // A long press lifts in Arranging, as a long press on a node does.
    maybeConstellationSelection(context)?.enterArranging();
    setState(() => _liftedTagId = tagId);
    return constellationGraphNodeIdForTarget(handle);
  }

  void _lowerTagHull() {
    if (mounted && _liftedTagId != null) {
      setState(() => _liftedTagId = null);
    }
  }

  String? _tagHullIdAtScene(ConstellationCubit cubit, Offset scene) {
    _updateTagHullHitTester(cubit);
    return _tagHullHitTester?.tagHullAt(scene);
  }

  Future<void> _showTagHullMoveMenu(
    ConstellationCubit cubit,
    String tagId,
    Offset scene,
  ) async {
    final store = _peopleTags;
    if (store == null) {
      return;
    }
    final tag = store.tags.where((t) => t.id == tagId).firstOrNull;
    if (tag == null) {
      return;
    }
    final l10n = L10n.of(context)!;
    final box = _graphStackKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return;
    }
    final global = box.localToGlobal(
      cubit.graphController.sceneToViewportLocal(scene),
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(global);
    final chosen = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<bool>(
          value: true,
          child: Text(l10n.constellationTagHullMoveArea(tag.name)),
        ),
      ],
    );
    if (!mounted || chosen != true) {
      return;
    }
    _startTagHullMenuDrag(cubit, tagId, scene);
  }

  void _startTagHullMenuDrag(
    ConstellationCubit cubit,
    String tagId,
    Offset scene,
  ) {
    final store = _peopleTags;
    if (store == null) {
      return;
    }
    final handle = cubit.beginDragTagArea(
      tagId: tagId,
      peopleOfTag: store.peopleInTag,
      tagsOfPerson: store.tagsOfPerson,
    );
    if (handle == null) {
      return;
    }
    maybeConstellationSelection(context)?.enterArranging();
    final graphId = constellationGraphNodeIdForTarget(handle);
    final box = _graphStackKey.currentContext?.findRenderObject();
    if (box is RenderBox) {
      _lastPointerGlobal = box.localToGlobal(
        cubit.graphController.sceneToViewportLocal(scene),
      );
    }
    setState(() {
      _liftedTagId = tagId;
      _tagHullMenuDragNodeId = graphId;
    });
    _tickTagHullMenuDrag(cubit, _lastPointerGlobal);
  }

  void _tickTagHullMenuDrag(ConstellationCubit cubit, Offset? global) {
    final graphId = _tagHullMenuDragNodeId;
    if (graphId == null || global == null) {
      return;
    }
    final scene = cubit.graphController.globalToScene(global);
    if (scene == null) {
      return;
    }
    final payload = cubit.graphController.nodePayloadForId(graphId);
    if (payload is! NodeDetails) {
      return;
    }
    final clamped = cubit.clampClusterDragPosition(payload, scene);
    cubit.updateDragPresentation(nodeId: graphId, sceneCentre: clamped);
    _syncComposerPersonPositions(cubit, maybeConstellationComposer(context));
  }

  void _finishTagHullMenuDrag(ConstellationCubit cubit) {
    final graphId = _tagHullMenuDragNodeId;
    if (graphId == null) {
      return;
    }
    _tagHullMenuDragNodeId = null;
    final payload = cubit.graphController.nodePayloadForId(graphId);
    if (payload is! NodeDetails) {
      _lowerTagHull();
      cubit.onPointerCancelDuringDrag();
      return;
    }
    final global = _lastPointerGlobal;
    if (global == null) {
      _lowerTagHull();
      cubit.onPointerCancelDuringDrag();
      return;
    }
    final scene = cubit.graphController.globalToScene(global);
    if (scene == null) {
      _lowerTagHull();
      cubit.onPointerCancelDuringDrag();
      return;
    }
    final clamped = cubit.clampClusterDragPosition(payload, scene);
    cubit.updateDragPresentation(nodeId: graphId, sceneCentre: clamped);
    _lowerTagHull();
    final target = cubit.state.activePlacementTarget;
    if (target == null) {
      cubit.onPointerCancelDuringDrag();
      return;
    }
    final composer = maybeConstellationComposer(context);
    switch (cubit.state.placementPhase) {
      case ConstellationPlacementPhase.draggingExisting:
      case ConstellationPlacementPhase.draggingNew:
        unawaited(
          cubit
              .onExistingNodeDrop(target: target, sceneCentre: clamped)
              .then((_) => _syncComposerPersonPositions(cubit, composer)),
        );
      case ConstellationPlacementPhase.idle:
      case ConstellationPlacementPhase.composing:
        cubit.onPointerCancelDuringDrag();
    }
  }

  void _cancelTagHullMenuDrag(ConstellationCubit cubit) {
    if (_tagHullMenuDragNodeId == null && _liftedTagId == null) {
      return;
    }
    _tagHullMenuDragNodeId = null;
    _lowerTagHull();
    cubit.onPointerCancelDuringDrag();
  }

  ConstellationDetailLevel get _detail => _zoom.value;

  // Edges only depend on the camera through the stroke compensation (zoom
  // below 1), so pans and zooms above 1 must not repaint them.
  late final ValueNotifier<double> _edgeStrokeScale;
  late final Listenable _edgeRepaint;

  // Animated pan that keeps a tapped node beside its preview (#458).
  late final AnimationController _reveal;
  ({Offset from, Offset to})? _revealPan;
  bool _applyingReveal = false;
  Timer? _fieldSettleBackTimer;

  @override
  void initState() {
    super.initState();
    clipWebSemanticsLabels(_mapNodeSemanticsPrefix);
    if (!kReleaseMode) ConstellationPerf.startFrameReporting();
    _graphController = context.read<ConstellationCubit>().graphController;
    _zoom = _readZoomOrOwn()
      ..update(_graphController.cameraScale, gestureActive: false)
      ..addListener(_onZoomLevel);
    _edgeStrokeScale = ValueNotifier(_strokeScale());
    final cubit = context.read<ConstellationCubit>();
    _edgeRepaint = Listenable.merge([
      _edgeStrokeScale,
      cubit.forwardTreeEdgePulseTick,
    ]);
    _reveal = AnimationController(vsync: this, duration: _revealDuration)
      ..addListener(_onRevealTick);
    _graphController.cameraRevision.addListener(_onCamera);
    _graphController.addListener(_syncCameraViewportInsetsFromController);
    _minimapExpanded.addListener(_onMinimapExpandedChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _measureBottomChromeColumnHeight();
      _syncCameraViewportInsetsFromController();
    });
    WidgetsBinding.instance.addObserver(this);
    final peopleTags = _peopleTags;
    if (widget.peopleTagsEnabled && peopleTags != null) {
      unawaited(peopleTags.ensureLoaded().catchError((Object _) {}));
    }
    _magnetTagsSubscription = _peopleTags?.changes.listen((_) {
      if (!mounted || !_peopleTags.hasLoaded) return;
      context.read<ConstellationCubit>().refreshTagMagnets({
        for (final tag in _peopleTags.tags) tag.id,
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_minimapExpandedInitialized) {
      _minimapExpandedInitialized = true;
      _minimapExpanded.value =
          windowClassForWidth(MediaQuery.sizeOf(context).width) !=
          WindowClass.compact;
    }
  }

  // The screen provides the owner; a body mounted bare owns its own.
  ConstellationZoomLevelController _readZoomOrOwn() {
    try {
      return context.read<ConstellationZoomLevelController>();
    } on ProviderNotFoundException {
      return _ownZoom = ConstellationZoomLevelController();
    }
  }

  @override
  void dispose() {
    unawaited(_magnetTagsSubscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _graphController.removeListener(_syncCameraViewportInsetsFromController);
    _minimapExpanded.removeListener(_onMinimapExpandedChanged);
    _fieldSettleBackTimer?.cancel();
    _graphController.cameraRevision.removeListener(_onCamera);
    _zoom.removeListener(_onZoomLevel);
    _ownZoom?.dispose();
    _minimapExpanded.dispose();
    _reveal.dispose();
    _edgeStrokeScale.dispose();
    _mapFocus.dispose();
    if (!kReleaseMode) ConstellationPerf.stopFrameReporting();
    super.dispose();
  }

  /// A hidden tab loses the pointer, so a drag in progress ends as a cancel.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden) {
      maybeConstellationSelection(context)?.exitArranging();
      context.read<ConstellationCubit>().onTabHidden();
    }
  }

  void _exitArrangingIfActive() {
    maybeConstellationSelection(context)?.exitArranging();
  }

  double _strokeScale() {
    final scale = _graphController.cameraScale;
    return scale < 1 ? scale : 1;
  }

  void _onCamera() {
    if (!_applyingReveal) {
      // Anyone else moving the camera (a pan, zoom, fit) wins over the reveal.
      _stopReveal();
    }
    _edgeStrokeScale.value = _strokeScale();
    _zoom.update(
      _graphController.cameraScale,
      gestureActive: _pointersDown > 0,
    );
    _rescheduleFieldSettleBack();
  }

  void _rescheduleFieldSettleBack() {
    _fieldSettleBackTimer?.cancel();
    _fieldSettleBackTimer = null;
    if (!mounted ||
        _pointersDown > 0 ||
        _applyingReveal ||
        _revealPan != null) {
      return;
    }
    _fieldSettleBackTimer = Timer(_fieldSettleBackDelay, () {
      if (!mounted || _pointersDown > 0) {
        return;
      }
      _tryFieldSettleBack();
    });
  }

  void _tryFieldSettleBack() {
    if (_applyingReveal || _revealPan != null) {
      return;
    }
    final cubit = context.read<ConstellationCubit>();
    final panelVisible =
        cubit.state.selectedPersonId != null ||
        cubit.state.selectedRequestId != null;
    final target = cubit.fieldSettleBackRevealTarget(
      insets: _cameraViewportInsets(context, panelVisible),
    );
    if (target == null) {
      return;
    }
    _revealNode(
      context,
      cubit,
      target,
      contextPanelVisible: panelVisible,
    );
  }

  void _onZoomLevel() {
    setState(() {});
  }

  void _onRevealTick() {
    final pan = _revealPan;
    if (pan == null) {
      return;
    }
    final t = Curves.easeOutCubic.transform(_reveal.value);
    _applyingReveal = true;
    try {
      context.read<ConstellationCubit>().panCameraTo(
        Offset.lerp(pan.from, pan.to, t)!,
      );
    } finally {
      _applyingReveal = false;
    }
  }

  void _stopReveal() {
    if (_revealPan == null) {
      return;
    }
    _revealPan = null;
    _reveal.stop();
  }

  /// Pans (translation only, zoom kept) so [node] stays visible beside or
  /// above the panel its selection opened ([contextPanelVisible] true), or
  /// inside the map clear of whatever panel is open now.
  void _revealNode(
    BuildContext context,
    ConstellationCubit cubit,
    NodeDetails node, {
    bool contextPanelVisible = true,
  }) {
    _stopReveal();
    final pan = cubit.revealPanFor(
      node,
      insets: _cameraViewportInsets(context, contextPanelVisible),
      // On a phone the selection's sheet leaves a strip above it, and the
      // selected node is centred in that strip at every zoom (#974 spec),
      // not just kept clear of the sheet's edge.
      centreVertically: _compactContextPanelOpen(context, contextPanelVisible),
    );
    if (pan == null) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _applyingReveal = true;
      try {
        cubit.panCameraTo(pan.to);
      } finally {
        _applyingReveal = false;
      }
      return;
    }
    _revealPan = pan;
    unawaited(
      _reveal.forward(from: 0).whenComplete(() {
        if (identical(_revealPan, pan)) {
          _revealPan = null;
        }
      }),
    );
  }

  ConstellationPresentationFrameHolder get _frameHolder =>
      widget.presentationFrameHolder ?? _internalFrameHolder;

  void _scheduleLabelBudgetSync(BuildContext context, Size viewport) {
    final style = TenturaText.labelSmall(
      Theme.of(context).colorScheme.onSurface,
    );
    final reference = style.fontSize!;
    final ratio = MediaQuery.textScalerOf(context).scale(reference) / reference;
    final cubit = context.read<ConstellationCubit>();
    final hasForwardedLabel =
        cubit.state.composition?.beaconNodes.any(
          (node) => node.request?.heldState == ConstellationHeldState.forwarded,
        ) ??
        false;
    final requestLabelMaxLines = hasForwardedLabel
        ? kConstellationRequestMapLabelMaxLines
        : 2;
    final footprintKey = (
      Theme.of(context).brightness,
      Localizations.localeOf(context),
      ratio,
      requestLabelMaxLines,
    );
    final budgetDirty =
        _lastLabelBudgetViewport != viewport ||
        _lastLabelBudgetTextScale != ratio;
    final footprintDirty = _lastFootprintSyncKey != footprintKey;
    if (!budgetDirty && !footprintDirty) {
      return;
    }
    if (budgetDirty) {
      _lastLabelBudgetViewport = viewport;
      _lastLabelBudgetTextScale = ratio;
    }
    if (footprintDirty) {
      _lastFootprintSyncKey = footprintKey;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (budgetDirty) {
        cubit.updateLabelBudgetContext(
          viewport: viewport,
          textScaleFactor: ratio,
        );
      }
      if (footprintDirty) {
        _syncFootprintMetrics(context, requestLabelMaxLines);
      }
    });
  }

  void _syncFootprintMetrics(BuildContext context, int requestLabelMaxLines) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final style = TenturaText.labelSmall(scheme.onSurface);
    final padding = EdgeInsets.symmetric(
      horizontal: tt.iconTextGap,
      vertical: tt.tightGap,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final personPlate = measureConstellationLabelPlate(
      text: 'Ág',
      style: style,
      maxLines: 1,
      plateWidth: tt.graphLabelMaxWidthPerson,
      padding: padding,
      textScaler: textScaler,
      direction: direction,
    );
    final requestPlate = measureConstellationLabelPlate(
      text: List.filled(requestLabelMaxLines, 'Ág').join('\n'),
      style: style,
      maxLines: requestLabelMaxLines,
      plateWidth: tt.graphLabelMaxWidthRequest,
      padding: padding,
      textScaler: textScaler,
      direction: direction,
    );
    final chipSize = constellationOverflowChipSize(
      context,
      l10n.constellationMoreRequests(99),
    );
    context.read<ConstellationCubit>().updateFootprintMetrics(
      (
        labelGap: tt.tightGap,
        personLabelWidth: tt.graphLabelMaxWidthPerson,
        personLabelHeight: personPlate.height,
        requestLabelWidth: tt.graphLabelMaxWidthRequest,
        requestLabelHeight: requestPlate.height,
        chipWidth: chipSize.width,
        chipHeight: chipSize.height,
        badgeOverhang: constellationMarkerBadgeOverhang(tt),
      ),
    );
  }

  void _onNodeTap(
    BuildContext context,
    ConstellationCubit cubit,
    NodeDetails node,
  ) {
    if (ConstellationFieldBeaconMapChrome.suppressesPrimaryTap()) {
      return;
    }
    if (constellationSelectionTap(context, cubit, node)) return;
    cubit.selectMapNode(node);
    if (cubit.state.isComposing) {
      return;
    }
    final state = cubit.state;
    final opensPanel = switch (node) {
      FieldBeaconNode() => state.selectedRequestId != null,
      FieldPersonNode(:final person) =>
        person.id != cubit.viewerId && state.selectedPersonId == person.id,
      _ => false,
    };
    if (opensPanel) {
      // Keep the tapped node visible beside / above its panel (#458).
      _revealNode(context, cubit, node);
    }
    if (node case FieldPersonNode(
      :final person,
    ) when person.id != cubit.viewerId) {
      context.read<GraphPersonContextCubit>().selectProfile(
        person,
        intentional: true,
      );
    }
  }

  /// Whether the map's tap hit test (labels included) claims [local].
  bool _hitsMapNode(ConstellationCubit cubit, Offset local) {
    final frame = _frameHolder.frame;
    final controller = cubit.graphController;
    if (frame == null ||
        (frame.snapshot as GraphSceneSnapshot<NodeDetails, EdgeDetails>)
                .sceneRevision !=
            controller.sceneRevision ||
        frame.cameraRevision != controller.cameraRevision.value) {
      return false;
    }
    return resolveConstellationTap(frame, local) != null;
  }

  Future<void> _dismissRequestPreview(ConstellationCubit cubit) async {
    cubit.selectRequest(null);
  }

  /// Closes the open person or Request panel (#680). Focus that was inside
  /// the panel goes away with it, so it comes back to the map, where Tab and
  /// Escape keep working; focus already on a map node stays there.
  void _closePanelOnEscape(ConstellationCubit cubit) {
    final state = cubit.state;
    if (state.selectedPersonId != null) {
      cubit.selectPerson(null);
    } else if (state.selectedRequestId != null) {
      unawaited(_dismissRequestPreview(cubit));
    } else {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (focus == null ||
          (focus != _mapFocus && !focus.ancestors.contains(_mapFocus))) {
        _mapFocus.requestFocus();
      }
    });
  }

  /// A press on the map, or select mode turned on from the toolbar, gives the
  /// map keyboard focus, so Escape then closes the panel or leaves select
  /// mode (#680). Focus already on the map or in its panels stays where it
  /// is, and a text field keeps its focus.
  void _takeMapFocus() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null) {
      if (focus == _mapFocus || focus.ancestors.contains(_mapFocus)) return;
      final focusContext = focus.context;
      if (focusContext != null &&
          (focusContext.widget is EditableText ||
              focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                  null)) {
        return;
      }
    }
    _mapFocus.requestFocus();
  }

  /// A click on an empty spot of the map clears the person or Request
  /// selection and closes its panel (#680). Placing, composing and the
  /// multi-select tools keep their own handling of the map.
  void _onEmptyMapTap(BuildContext context, ConstellationCubit cubit) {
    final state = cubit.state;
    if (state.forwardTreeOverlay != null) {
      cubit.exitForwardTreeMode();
      return;
    }
    if (state.isComposing ||
        state.placementPhase != ConstellationPlacementPhase.idle) {
      return;
    }
    // Select mode and the sector own the map's taps. Nodes still selected
    // after select mode was turned off do not: the click closes the panel.
    final selection = maybeConstellationSelection(context);
    if (selection != null &&
        (selection.state.selecting ||
            selection.state.sector != null ||
            ConstellationSelectionCubit.modifierHeld)) {
      return;
    }
    if (state.selectedPersonId != null) cubit.selectPerson(null);
    if (cubit.state.selectedRequestId != null) {
      unawaited(_dismissRequestPreview(cubit));
    }
  }

  void _openBeacon(
    BuildContext context,
    String beaconId, {
    String? viewTab,
  }) {
    _exitArrangingIfActive();
    context.read<ConstellationCubit>().openedFieldBeacon(beaconId);
    unawaited(() async {
      await GetIt.I<AppNavigator>().openBeacon(beaconId, viewTab: viewTab);
      if (context.mounted) await context.read<ConstellationCubit>().load();
    }());
  }

  VoidCallback _primaryActionForRequest(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) {
    return switch (request.heldState) {
      ConstellationHeldState.mine ||
      ConstellationHeldState.participant ||
      ConstellationHeldState.forwarded => () => _openBeacon(
        context,
        request.id,
      ),
      ConstellationHeldState.offered => () => _openBeacon(
        context,
        request.id,
        viewTab: constellationHeldOpenViewTab(request.heldState),
      ),
      ConstellationHeldState.none => () {
        unawaited(
          _runOfferFlowAndMaybeReopenPreview(
            context,
            cubit,
            request,
          ),
        );
      },
    };
  }

  Future<void> _runForwardFlow(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) async {
    final preflight = await cubit.preflightRequestAction(request.id);
    if (!context.mounted) {
      return;
    }
    switch (preflight) {
      case ConstellationRequestPreflightAuthorizationDenied(:final message):
        _showActionMessage(context, message);
      case ConstellationRequestPreflightUnavailable(:final message):
        _showActionMessage(context, message);
      case ConstellationRequestPreflightReady(:final request):
        _exitArrangingIfActive();
        await GetIt.I<AppNavigator>().forwardBeacon(request.id);
    }
  }

  Future<void> _runOfferFlowAndMaybeReopenPreview(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) async {
    final requestId = request.id;
    await _dismissRequestPreview(cubit);
    if (!context.mounted) {
      return;
    }
    final reShow = await _runOfferFlow(context, cubit, request);
    if (reShow != null && context.mounted) {
      cubit.selectRequest(requestId);
    }
  }

  Future<ConstellationRequest?> _runOfferFlow(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest snapshotRequest, {
    String? preservedMessage,
    List<String>? preservedHelpTypes,
  }) async {
    final preflight = await cubit.preflightRequestAction(snapshotRequest.id);
    if (!context.mounted) {
      return null;
    }
    switch (preflight) {
      case ConstellationRequestPreflightAuthorizationDenied(:final message):
        _showActionMessage(context, message);
        return null;
      case ConstellationRequestPreflightUnavailable(:final message):
        _showActionMessage(context, message);
        return null;
      case ConstellationRequestPreflightReady(
        :final request,
        :final viewerHasActiveHelpOffer,
      ):
        if (cubit.coverageRequiresExplicitBackupChoice(
          snapshotRequest: snapshotRequest,
          freshRequest: request,
        )) {
          _showActionMessage(
            context,
            'Help is now covered. Choose whether to offer as backup.',
          );
          return request;
        }
        final expectedOfferKind = cubit.expectedOfferKindForRequest(request);
        final useBackupCopy = expectedOfferKind == 1;
        final l10n = L10n.of(context)!;
        final outcome = await HelpOfferMessageDialog.show(
          context,
          title: useBackupCopy
              ? l10n.dialogOfferHelpAnywayTitle
              : l10n.dialogOfferHelpTitle,
          hintText: l10n.hintOfferHelpMessage,
          initialText: preservedMessage ?? '',
          showHelpTypeChips: true,
          initialHelpTypeSlugs: preservedHelpTypes?.toSet() ?? const {},
          automaticSlugs: request.needs.toSet(),
        );
        if (outcome == null || !context.mounted) {
          return null;
        }
        final submit = await cubit.submitValidatedOfferHelp(
          beaconId: request.id,
          expectedOfferKind: expectedOfferKind,
          message: outcome.message,
          helpTypes: viewerHasActiveHelpOffer
              ? normalizeOfferHelpTypesWire(outcome.helpTypesWire)
              : outcome.helpTypesWire,
        );
        if (!context.mounted) {
          return null;
        }
        switch (submit) {
          case ConstellationOfferSubmitOutcome.success:
            _showActionMessage(context, l10n.labelOfferHelp);
            return null;
          case ConstellationOfferSubmitOutcome.offerKindChanged:
            _showActionMessage(
              context,
              'Coverage changed. Choose how you want to help.',
            );
            final refreshed = cubit.requestById(request.id) ?? request;
            return _runOfferFlow(
              context,
              cubit,
              refreshed,
              preservedMessage: outcome.message,
              preservedHelpTypes: outcome.helpTypesWire,
            );
          case ConstellationOfferSubmitOutcome.validationFailed:
            _showActionMessage(
              context,
              'Could not submit your offer. Try again.',
            );
            return _runOfferFlow(
              context,
              cubit,
              request,
              preservedMessage: outcome.message,
              preservedHelpTypes: outcome.helpTypesWire,
            );
        }
    }
  }

  Future<void> _unblockPerson(BuildContext context, String personId) async {
    try {
      await GetIt.I<BlockCase>().unblock(objectId: personId);
    } on Object catch (error) {
      if (context.mounted) {
        _showActionMessage(context, error.toString());
      }
    }
  }

  void _showActionMessage(BuildContext context, String message) {
    showSnackBar(context, text: message);
  }

  EdgeInsets _cameraViewportInsetsFromContext(
    BuildContext context,
    bool contextPanelVisible,
  ) {
    final tt = context.tt;
    final compactSheet =
        contextPanelVisible && context.windowClass == WindowClass.compact;
    final sheetHeight = compactSheet
        ? (_compactSheetHeight > 0
              ? _compactSheetHeight
              : _effectiveMapStackHeight * tt.fieldSheetPeekFraction)
        : 0.0;
    return ConstellationCameraControls.cameraViewportInsets(
      context,
      contextPanelVisible: contextPanelVisible,
      compactSheetHeight: sheetHeight,
      bottomChromeHeight: _bottomChromeColumnHeight,
      minimapExpanded: _minimapExpanded.value,
    );
  }

  EdgeInsets _cameraViewportInsets(
    BuildContext context,
    bool contextPanelVisible,
  ) => _cameraViewportInsetsFromContext(context, contextPanelVisible);

  bool _compactContextPanelOpen(
    BuildContext context,
    bool panelVisible,
  ) => panelVisible && context.windowClass == WindowClass.compact;

  void _onCompactSheetExtentChanged(double height) {
    if ((_compactSheetHeight - height).abs() < 0.5) {
      return;
    }
    setState(() => _compactSheetHeight = height);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final cubit = context.read<ConstellationCubit>();
      final state = cubit.state;
      final node = _selectedMapNode(cubit, state);
      if (node != null) {
        _revealNode(context, cubit, node);
      }
    });
  }

  void _onCompactSheetDetentExpanded(bool expanded) {
    if (_compactSheetDetentExpanded == expanded) {
      return;
    }
    setState(() => _compactSheetDetentExpanded = expanded);
    final report = widget.onFieldContextSheetExpandedChanged;
    if (report == null) {
      return;
    }
    final state = context.read<ConstellationCubit>().state;
    final panelVisible =
        state.selectedPersonId != null || state.selectedRequestId != null;
    if (!_compactContextPanelOpen(context, panelVisible)) {
      report(false);
      return;
    }
    report(expanded);
  }

  NodeDetails? _selectedMapNode(
    ConstellationCubit cubit,
    ConstellationState state,
  ) {
    for (final node
        in cubit.graphController.renderSnapshot.topology.nodesById.values) {
      final payload = node.payload;
      if (payload is FieldPersonNode) {
        if (payload.person.id == state.selectedPersonId) {
          return payload;
        }
      } else if (payload is FieldBeaconNode) {
        if (payload.request?.id == state.selectedRequestId ||
            payload.post?.id == state.selectedRequestId) {
          return payload;
        }
      }
    }
    return null;
  }

  void _dismissCompactContextPanel(ConstellationCubit cubit) {
    final state = cubit.state;
    if (state.selectedPersonId != null) {
      cubit.selectPerson(null);
    } else if (state.selectedRequestId != null) {
      unawaited(_dismissRequestPreview(cubit));
    }
  }

  void _syncCompactPanelSideEffects(
    BuildContext context,
    ConstellationCubit cubit,
    bool panelVisible,
  ) {
    final compactOpen = _compactContextPanelOpen(context, panelVisible);
    if (!compactOpen && _wasCompactPanelOpen && _compactSheetHeight != 0) {
      setState(() {
        _compactSheetHeight = 0;
        _compactSheetDetentExpanded = false;
      });
    }
    _wasCompactPanelOpen = compactOpen;
  }

  void _scheduleFieldContextSheetExpandedReport() {
    if (widget.onFieldContextSheetExpandedChanged == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _reportFieldContextSheetExpanded();
    });
  }

  void _reportFieldContextSheetExpanded() {
    final report = widget.onFieldContextSheetExpandedChanged;
    if (report == null) {
      return;
    }
    final state = context.read<ConstellationCubit>().state;
    final panelVisible =
        state.selectedPersonId != null || state.selectedRequestId != null;
    if (!_compactContextPanelOpen(context, panelVisible)) {
      report(false);
      return;
    }
    report(_compactSheetDetentExpanded);
  }

  void _noteMapStackHeight(double height) {
    if ((_mapStackHeight - height).abs() < 0.5) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (_mapStackHeight - height).abs() < 0.5) {
        return;
      }
      setState(() => _mapStackHeight = height);
    });
  }

  void _measureFieldTopChromeHeight() {
    final box = _fieldTopChromeKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final height = box.size.height;
    if ((_fieldTopChromeHeight - height).abs() < 0.5) {
      return;
    }
    _fieldTopChromeHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _measureBottomChromeColumnHeight() {
    final box = _bottomChromeColumnKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    final h = box.size.height;
    if ((_bottomChromeColumnHeight - h).abs() < 0.5) {
      return;
    }
    setState(() => _bottomChromeColumnHeight = h);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncCameraViewportInsetsFromController();
    });
  }

  void _onMinimapExpandedChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    _syncCameraViewportInsetsFromController();
  }

  void _syncCameraViewportInsetsFromController() {
    if (!mounted) {
      return;
    }
    final cubit = context.read<ConstellationCubit>();
    final panelVisible =
        cubit.state.selectedPersonId != null ||
        cubit.state.selectedRequestId != null;
    final snapshotInsets = _cameraViewportInsetsFromContext(
      context,
      panelVisible,
    );
    cubit.syncFieldCameraViewportFromBody(
      snapshotInsets: snapshotInsets,
      bottomChromeHeight: _bottomChromeColumnHeight,
      minimapExpanded: _minimapExpanded.value,
    );
  }

  Widget _wrapAdaptiveContextOverlay(
    BuildContext context,
    ConstellationCubit cubit,
    Widget child, {
    required double mapStackHeight,
  }) {
    final useDetents = context.windowClass == WindowClass.compact;
    return AdaptiveContextOverlay(
      compactDetents: useDetents,
      mapStackHeight: useDetents ? mapStackHeight : null,
      onDismiss: useDetents ? () => _dismissCompactContextPanel(cubit) : null,
      onCompactExtentChanged: useDetents ? _onCompactSheetExtentChanged : null,
      onCompactDetentExpandedChanged: useDetents
          ? _onCompactSheetDetentExpanded
          : null,
      child: child,
    );
  }

  Widget _buildContextOverlay(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state, {
    required double mapStackHeight,
  }) {
    final personId = state.selectedPersonId;
    if (personId != null && personId != cubit.viewerId) {
      if (cubit.fieldPersonById(personId)?.pinState == 'tombstone') {
        return _wrapAdaptiveContextOverlay(
          context,
          cubit,
          ConstellationPinPlaceholderSheet(
            target: ConstellationAnchorTarget.person(personId),
            pinState: 'accountDeleted',
            onClose: () => cubit.selectPerson(null),
          ),
          mapStackHeight: mapStackHeight,
        );
      }
      final profile = cubit.profileForPersonId(personId);
      if (profile == null) {
        return const SizedBox.shrink();
      }
      return _wrapAdaptiveContextOverlay(
        context,
        cubit,
        GraphPersonContextPanel(
          profile: profile,
          isBlocked: cubit.fieldPersonById(personId)?.pinState == 'blockedByMe',
          onUnblock: () => unawaited(_unblockPerson(context, personId)),
          focusedNode: UserNode(user: profile),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cubit.fieldPersonById(personId)?.pinState == 'blockedByMe')
                TenturaStatusText(L10n.of(context)!.constellationPinBlocked),
              if (widget.fieldMembershipV2Enabled)
                ConstellationPresenceLine(personId: personId),
              ConstellationTrustChainLine(personId: personId),
            ],
          ),
          personFieldItemsSection: cubit.personFieldItemsCase == null
              ? null
              : ConstellationPersonFieldItemsSection(personId: personId),
          discoverableRequests: cubit.personFieldItemsCase == null
              ? cubit.discoverableRequestsForPerson(personId)
              : const [],
          requestsExpanded: state.expandedPersonIds.contains(personId),
          onToggleRequestsExpanded: cubit.personFieldItemsCase == null
              ? () => cubit.togglePersonRequestsExpanded(personId)
              : null,
          onDiscoverableRequestTap: cubit.personFieldItemsCase == null
              ? (request) {
                  cubit
                    ..selectPerson(null)
                    ..selectRequest(request.id);
                }
              : null,
          footer: ConstellationAnchorTargetButton(
            target: ConstellationAnchorTarget.person(personId),
          ),
        ),
        mapStackHeight: mapStackHeight,
      );
    }

    final requestId = state.selectedRequestId;
    if (requestId == null) {
      return const SizedBox.shrink();
    }
    final request = cubit.requestById(requestId);
    if (request == null) {
      final post = cubit.postById(requestId);
      if (post != null) {
        return _wrapAdaptiveContextOverlay(
          context,
          cubit,
          ConstellationPostPreviewSheet(
            post: post,
            authorDisplayName:
                cubit.profileForPersonId(post.authorId)?.shownName ?? '',
            onOpen: () => _openBeacon(context, post.id),
            onOpenParticipants: () =>
                constellationFieldPreviewOpenPostParticipants(
                  () => _openBeacon(context, post.id),
                  post.id,
                ),
            onOpenForwardedThrough: () =>
                constellationFieldPreviewOpenPostParticipants(
                  () => _openBeacon(context, post.id),
                  post.id,
                ),
            onClose: () => cubit.selectRequest(null),
          ),
          mapStackHeight: mapStackHeight,
        );
      }
      return const SizedBox.shrink();
    }

    final author = cubit.profileForPersonId(request.authorId);
    final authorDisplayName = author?.shownName ?? '';
    final paths = state.paths;
    final throughPeerId = paths == null
        ? null
        : constellationConnectionThroughPeerId(
            egoId: cubit.viewerId,
            authorId: request.authorId,
            parent: paths.parent,
          );
    final connectionThroughName = throughPeerId == null
        ? null
        : cubit.profileForPersonId(throughPeerId)?.shownName;

    return _wrapAdaptiveContextOverlay(
      context,
      cubit,
      ConstellationRequestPreviewSheet(
        request: request,
        authorDisplayName: authorDisplayName,
        connectionThroughName: connectionThroughName,
        onOpen: () => _openBeacon(context, request.id),
        onPrimaryAction: _primaryActionForRequest(context, cubit, request),
        onForward: constellationPreviewShowsForward(request)
            ? () => unawaited(_runForwardFlow(context, cubit, request))
            : null,
        onShowForwardTreeOnField: request.viewerHasForwardEdge
            ? () => context.read<ScreenCubit>().showConstellationForwardTreeFor(
                beaconId: request.id,
              )
            : null,
        onOpenParticipants: () => _openBeacon(
          context,
          request.id,
          viewTab: kBeaconViewTabPeople,
        ),
        onOpenForwardedThrough: request.viewerHasForwardEdge
            ? () => context.read<ScreenCubit>().showConstellationForwardTreeFor(
                beaconId: request.id,
              )
            : () => _openBeacon(
                context,
                request.id,
                viewTab: kBeaconViewTabPeople,
              ),
        onClose: () => unawaited(_dismissRequestPreview(cubit)),
      ),
      mapStackHeight: mapStackHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BrowserContextMenuHold(
      child: MultiBlocListener(
        listeners: [
          BlocListener<ConstellationCubit, ConstellationState>(
            listenWhen: (previous, current) =>
                previous.selectedRequestId != current.selectedRequestId &&
                current.selectedRequestId != null,
            listener: (context, state) {
              final requestId = state.selectedRequestId!;
              final cubit = context.read<ConstellationCubit>();
              final request = cubit.requestById(requestId);
              if (request != null || cubit.isPostId(requestId)) {
                setState(() => _selectionUnavailableMessage = null);
                return;
              }
              final message = L10n.of(
                context,
              )!.constellationSelectionUnavailable;
              setState(() => _selectionUnavailableMessage = message);
              unawaited(
                SemanticsService.sendAnnouncement(
                  View.of(context),
                  message,
                  TextDirection.ltr,
                ),
              );
              cubit.selectRequest(null);
            },
          ),
          // Select mode turned on from the toolbar: Escape leaves it (#680).
          if (maybeConstellationSelection(context) case final selection?) ...[
            BlocListener<
              ConstellationSelectionCubit,
              ConstellationMultiSelection
            >(
              bloc: selection,
              listenWhen: (previous, current) =>
                  !previous.selecting && current.selecting,
              listener: (_, _) => _takeMapFocus(),
            ),
          ],
          BlocListener<GraphPersonContextCubit, GraphPersonContextState>(
            listenWhen: (previous, current) =>
                previous.dismissedFocusId != current.dismissedFocusId &&
                current.dismissedFocusId != null,
            listener: (context, state) {
              context.read<ConstellationCubit>().selectPerson(null);
            },
          ),
          BlocListener<ConstellationCubit, ConstellationState>(
            listenWhen: (previous, current) =>
                previous.visibility != current.visibility ||
                previous.field != current.field,
            listener: (context, state) {
              final selection = maybeConstellationSelection(context);
              if (selection == null || !selection.state.arranging) {
                return;
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) {
                  return;
                }
                if (!selection.state.arranging) {
                  return;
                }
                if (!context.read<ConstellationCubit>().canArrange) {
                  selection.exitArranging();
                }
              });
            },
          ),
          BlocListener<ConstellationCubit, ConstellationState>(
            listenWhen: (previous, current) =>
                previous.selectedPersonId != current.selectedPersonId ||
                previous.selectedRequestId != current.selectedRequestId,
            listener: (context, state) {
              final cubit = context.read<ConstellationCubit>();
              final panelVisible =
                  state.selectedPersonId != null ||
                  state.selectedRequestId != null;
              _syncCompactPanelSideEffects(context, cubit, panelVisible);
              _scheduleFieldContextSheetExpandedReport();
            },
          ),
        ],
        child: BlocBuilder<ConstellationCubit, ConstellationState>(
          buildWhen: (previous, current) =>
              (previous.graphRevision != current.graphRevision &&
                  context
                          .read<ConstellationCubit>()
                          .graphSceneLayoutAlgorithm !=
                      _mountedLayoutAlgorithm) ||
              previous.status != current.status ||
              previous.loadError != current.loadError ||
              previous.selectedPersonId != current.selectedPersonId ||
              previous.selectedRequestId != current.selectedRequestId ||
              previous.expandedPersonIds != current.expandedPersonIds ||
              previous.viewMode != current.viewMode ||
              previous.tagView != current.tagView ||
              previous.rearrangePreview != current.rearrangePreview ||
              previous.loadedAt != current.loadedAt ||
              previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
              previous.filterLocation != current.filterLocation ||
              previous.filterTiming != current.filterTiming ||
              previous.filterIncludeUnspecified !=
                  current.filterIncludeUnspecified ||
              previous.membershipFilters != current.membershipFilters,
          builder: (context, state) {
            return LayoutBuilder(
              builder: (context, constraints) {
                _scheduleLabelBudgetSync(
                  context,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
                final cubit = context.read<ConstellationCubit>();
                final tt = context.tt;

                if (state.status is StateIsLoading && state.field == null) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      const Center(child: TenturaCircularProgress()),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearPiActive.builder(context, true),
                      ),
                    ],
                  );
                }

                if (state.loadError != null && state.field == null) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.screenHPadding,
                      ),
                      child: Text(
                        state.loadError.toString(),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                }

                final resolved = state.resolvedField;
                if (resolved == null || cubit.layoutEgoId.isEmpty) {
                  return const SizedBox.shrink();
                }

                final panelVisible =
                    state.selectedPersonId != null ||
                    state.selectedRequestId != null;
                final compactPanel = _compactContextPanelOpen(
                  context,
                  panelVisible,
                );
                final compactSheetExpanded = _compactSheetDetentExpanded;

                return Shortcuts(
                  shortcuts: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        const _CancelPlacementIntent(),
                    if (widget.arrangeV2Enabled) ...{
                      for (final (control, meta) in const [
                        (true, false),
                        (false, true),
                      ]) ...{
                        SingleActivator(
                          LogicalKeyboardKey.keyZ,
                          control: control,
                          meta: meta,
                        ): const _UndoArrangementIntent(),
                        SingleActivator(
                          LogicalKeyboardKey.keyZ,
                          control: control,
                          meta: meta,
                          shift: true,
                        ): const _RedoArrangementIntent(),
                      },
                    },
                  },
                  child: Actions(
                    actions: {
                      _UndoArrangementIntent:
                          CallbackAction<_UndoArrangementIntent>(
                            onInvoke: (_) {
                              unawaited(cubit.undoArrangement());
                              return null;
                            },
                          ),
                      _RedoArrangementIntent:
                          CallbackAction<_RedoArrangementIntent>(
                            onInvoke: (_) {
                              unawaited(cubit.redoArrangement());
                              return null;
                            },
                          ),
                      _CancelPlacementIntent:
                          CallbackAction<_CancelPlacementIntent>(
                            onInvoke: (_) {
                              // Select mode and the sector step back first;
                              // nodes left selected after select mode only
                              // once the open panel is closed (#680).
                              final selection = maybeConstellationSelection(
                                context,
                              );
                              final panelOpen =
                                  cubit.state.selectedPersonId != null ||
                                  cubit.state.selectedRequestId != null;
                              if (!cubit.state.isComposing &&
                                  cubit.state.placementPhase ==
                                      ConstellationPlacementPhase.idle &&
                                  selection != null &&
                                  (selection.state.arranging ||
                                      selection.state.selecting ||
                                      selection.state.sector != null ||
                                      !panelOpen) &&
                                  selection.escape()) {
                                return null;
                              }
                              final composer = maybeConstellationComposer(
                                context,
                              );
                              if (cubit.state.isComposing && composer != null) {
                                unawaited(() async {
                                  await composer.cancel();
                                  await composer.finish();
                                }());
                              } else {
                                final placing =
                                    cubit.state.placementPhase !=
                                    ConstellationPlacementPhase.idle;
                                if (_tagHullMenuDragNodeId != null ||
                                    (_liftedTagId != null && placing)) {
                                  _cancelTagHullMenuDrag(cubit);
                                } else {
                                  cubit.cancelPlacement();
                                }
                                // Nothing else to cancel: Escape closes the
                                // person or Request panel (#680).
                                if (!placing) _closePanelOnEscape(cubit);
                              }
                              return null;
                            },
                          ),
                    },
                    child: Listener(
                      onPointerDown: (e) {
                        _lastPointerGlobal = e.position;
                        _lastTagChipDropHint = null;
                      },
                      onPointerMove: (e) => _lastPointerGlobal = e.position,
                      child: Focus(
                        focusNode: _mapFocus,
                        autofocus: true,
                        child: LayoutBuilder(
                          builder: (context, bodyConstraints) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCappedFieldTopChrome(
                                context,
                                bodyConstraints.maxHeight,
                                state,
                                cubit,
                                hideMapChrome: compactPanel,
                              ),
                              Expanded(
                                child: IndexedStack(
                                  index:
                                      state.viewMode ==
                                          ConstellationViewMode.map
                                      ? 0
                                      : 1,
                                  sizing: StackFit.expand,
                                  children: [
                                    ValueListenableBuilder<int>(
                                      valueListenable: cubit
                                          .graphController
                                          .topologyRevision,
                                      // Labels and chips drawn near the top edge
                                      // pass under the chip row, as edges do: the
                                      // clip stops their paint and hits at the
                                      // map's edge (#675).
                                      builder: (context, _, _) {
                                        Widget graphStack() => LayoutBuilder(
                                          builder: (context, mapConstraints) {
                                            _layoutMapStackHeight =
                                                mapConstraints.maxHeight;
                                            _noteMapStackHeight(
                                              mapConstraints.maxHeight,
                                            );
                                            return ClipRect(
                                              child: _buildGraphStack(
                                                context,
                                                cubit,
                                                cubit.state,
                                                cubit.graphSceneLayoutAlgorithm,
                                                panelVisible,
                                                compactSheetExpanded,
                                              ),
                                            );
                                          },
                                        );
                                        // [touchNodeDragLocked] must track Arranging.
                                        final selection =
                                            maybeConstellationSelection(
                                              context,
                                            );
                                        if (selection == null) {
                                          return graphStack();
                                        }
                                        return BlocBuilder<
                                          ConstellationSelectionCubit,
                                          ConstellationMultiSelection
                                        >(
                                          bloc: selection,
                                          buildWhen: (previous, current) =>
                                              previous.arranging !=
                                              current.arranging,
                                          builder: (context, _) => graphStack(),
                                        );
                                      },
                                    ),
                                    // The map stack hosts the preview overlay; the
                                    // text view needs its own or a tapped card shows
                                    // nothing (#354).
                                    Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Not mounted while hidden: its Pin
                                        // buttons would keep running pin layouts
                                        // on every map recompose.
                                        if (state.viewMode ==
                                            ConstellationViewMode.text) ...[
                                          const ConstellationTextView(),
                                          if (panelVisible)
                                            _buildContextOverlay(
                                              context,
                                              cubit,
                                              state,
                                              mapStackHeight:
                                                  _effectiveMapStackHeight,
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildCappedFieldTopChrome(
    BuildContext context,
    double bodyHeight,
    ConstellationState state,
    ConstellationCubit cubit, {
    required bool hideMapChrome,
  }) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final capHeight = bodyHeight * tt.fieldTopChromeMaxFraction;
    if (hideMapChrome) {
      return const SizedBox.shrink();
    }
    _measureFieldTopChromeHeight();
    final selection = maybeConstellationSelection(context);
    final topChrome = SingleChildScrollView(
      child: Column(
        key: _fieldTopChromeKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!state.isComposing) ...[
            const ConstellationFieldNotices(),
            const ConstellationEmptyFilterBanner(),
            const ConstellationNoContactsBanner(),
            const ConstellationVisibilityBar(),
          ],
          if (_selectionUnavailableMessage != null)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.screenHPadding,
                  vertical: tt.tightGap,
                ),
                child: Text(
                  _selectionUnavailableMessage!,
                  key: const Key('constellation.selection_unavailable'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (!state.isComposing) _buildTagRow(context),
          if (state.tagView case final view?)
            _buildTagViewHeader(context, cubit, view),
          if (state.rearrangePreview case final preview?)
            ConstellationRearrangePreviewBar(
              movingCount: preview.movingCount,
              onApply: () => unawaited(cubit.applyRearrangePreview()),
              onCancel: cubit.cancelRearrangePreview,
            ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: capHeight),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          topChrome,
          if (selection != null)
            BlocBuilder<
              ConstellationSelectionCubit,
              ConstellationMultiSelection
            >(
              bloc: selection,
              buildWhen: (previous, current) =>
                  previous.arranging != current.arranging,
              builder: (context, selectionState) {
                if (!selectionState.arranging) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: ConstellationArrangingToolbar(
                      cubit: cubit,
                      peopleTagsEnabled: widget.peopleTagsEnabled,
                      topEmbedded: true,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTagRow(BuildContext context) {
    final cubit = context.read<ConstellationCubit>();
    final field = cubit.state.field;
    if (field == null ||
        constellationFieldHasNoContacts(field, cubit.viewerId)) {
      return const SizedBox.shrink();
    }
    final store = _peopleTags;
    final lensCubit = maybeConstellationTagLens(context);
    if (store == null || lensCubit == null) return const SizedBox.shrink();
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tt.tightGap),
      child: StreamBuilder<void>(
        stream: store.changes,
        builder: (context, _) =>
            BlocBuilder<ConstellationTagLensCubit, ConstellationTagFilter>(
              bloc: lensCubit,
              builder: (context, filter) => ConstellationTagRow(
                ownTags: store.tags,
                onPlaceMagnet:
                    context.read<ConstellationCubit>().state.tagView == null &&
                        widget.peopleTagsEnabled
                    ? _placeTagMagnet
                    : null,
                onMagnetDrop: _placeTagMagnet,
                autoTags: ConstellationAutoTagKind.values,
                filter: filter,
                onToggleOwn: lensCubit.toggleOwn,
                onToggleAuto: lensCubit.toggleAuto,
                onModeChanged: lensCubit.setMode,
                onAddTag: () => unawaited(
                  showTagEditorDialog(
                    context,
                    onSave: (name, glyph, color) => store.createTag(
                      name: name,
                      glyph: glyph,
                      color: color,
                    ),
                  ),
                ),
                onShowAll: () => showConstellationAllTagsSheet(
                  context: context,
                  lensCubit: lensCubit,
                  ownTags: store.tags,
                  autoTags: ConstellationAutoTagKind.values,
                  onAddTag: () => unawaited(
                    showTagEditorDialog(
                      context,
                      onSave: (name, glyph, color) => store.createTag(
                        name: name,
                        glyph: glyph,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }

  Widget _buildTagViewHeader(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationTagView view,
  ) {
    final store = _peopleTags;
    final l10n = L10n.of(context)!;
    final ownTags = [
      for (final tag in store?.tags ?? const <PersonTag>[])
        if (view.filter.selectedOwn.contains(tag.id)) tag,
    ];
    final names = [
      for (final tag in ownTags) tag.name,
      for (final kind in view.filter.selectedAuto)
        constellationAutoTagName(l10n, kind),
    ];
    return ConstellationTagViewHeader(
      title: l10n.constellationTagViewHeader(
        names.join(', '),
        view.scope.memberIds.length,
      ),
      colorIndex: ownTags.isEmpty ? 0 : ownTags.first.color,
      others: view.others,
      members: [
        for (final person in cubit.fieldPeople)
          if (view.scope.memberIds.contains(person.id)) person,
      ],
      onOthers: cubit.setTagViewOthers,
      onFound: cubit.selectPerson,
      onForward: () => unawaited(
        _forwardFromTagLens(context, cubit, view.filter.selectedOwn),
      ),
      onExit: cubit.exitTagView,
    );
  }

  /// Scene background of the map: the tag hulls, then the composer circle.
  Widget _buildCanvasBackground(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationComposerCubit? composer,
  ) {
    final store = _peopleTags;
    final lensCubit = maybeConstellationTagLens(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The topographic backdrop (#1022) lies under everything, hulls too.
        if (ConstellationFieldTopoBackdrop.enabled)
          ConstellationFieldTopoBackdrop(
            camera: cubit.graphController.cameraRevision,
            cameraScale: () => cubit.graphController.cameraScale,
          ),
        if (store != null && lensCubit != null)
          StreamBuilder<void>(
            stream: store.changes,
            builder: (context, _) =>
                BlocBuilder<ConstellationTagLensCubit, ConstellationTagFilter>(
                  bloc: lensCubit,
                  builder: (context, filter) {
                    final fieldIds = {
                      for (final person in cubit.fieldPeople) person.id,
                    };
                    return ConstellationTagHullLayer(
                      controller: cubit.graphController,
                      tags: [
                        for (final tag in store.tags)
                          if (store.peopleInTag(tag.id).any(fieldIds.contains))
                            tag,
                      ],
                      selectedTagIds: filter.selectedOwn,
                      liftedTagId: _liftedTagId,
                      peopleOf: store.peopleInTag,
                    );
                  },
                ),
          ),
        BlocBuilder<ConstellationCubit, ConstellationState>(
          bloc: cubit,
          buildWhen: (previous, current) => previous.tagView != current.tagView,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              for (final MapEntry(:key, :value)
                  in cubit.tagViewDotPositions.entries)
                Positioned(
                  key: Key('constellation-tag-view-dot-$key'),
                  left: value.dx - _tagViewDotRadius,
                  top: value.dy - _tagViewDotRadius,
                  child: IgnorePointer(
                    child: Container(
                      width: _tagViewDotRadius * 2,
                      height: _tagViewDotRadius * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (composer != null) ConstellationComposerCircle(composer: composer),
      ],
    );
  }

  static const _tagViewDotRadius = 6.0;

  /// The lens summary and "Forward a request…", while a tag is selected.
  Widget _buildTagLensPanel(BuildContext context, ConstellationCubit cubit) {
    final store = _peopleTags;
    final lensCubit = maybeConstellationTagLens(context);
    if (store == null || lensCubit == null) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    return StreamBuilder<void>(
      stream: store.changes,
      builder: (context, _) =>
          BlocBuilder<ConstellationTagLensCubit, ConstellationTagFilter>(
            bloc: lensCubit,
            builder: (context, filter) {
              // The tag view carries its own summary and forward action.
              if (filter.isEmpty ||
                  cubit.state.isComposing ||
                  cubit.state.tagView != null) {
                return const SizedBox.shrink();
              }
              final canOpenTagView = constellationTagViewEntryAvailable(
                peopleTagsEnabled: widget.peopleTagsEnabled,
                arrangeV2Enabled: widget.arrangeV2Enabled,
              );
              final field = cubit.state.field;
              final lens = _tagLensFor(cubit, lensCubit, filter);
              final people = {
                for (final person
                    in field?.peers ?? const <ConstellationPerson>[])
                  if (lens.brightPersonIds.contains(person.id)) person.id,
              };
              final tags = [
                for (final tag in store.tags)
                  if (filter.selectedOwn.contains(tag.id)) tag.name,
                for (final kind in filter.selectedAuto)
                  constellationAutoTagName(l10n, kind),
              ];
              return ConstellationTagLensPanel(
                tagNames: tags,
                peopleCount: people.length,
                requestCount: [
                  for (final request
                      in field?.requests ?? const <ConstellationRequest>[])
                    if (people.contains(request.authorId)) request,
                ].length,
                onOpenTagView: canOpenTagView
                    ? () => cubit.enterTagView(
                        filter: filter,
                        ownTagIdsOf: store.tagsOfPerson,
                      )
                    : null,
                onForward: () => unawaited(
                  _forwardFromTagLens(
                    context,
                    cubit,
                    filter.selectedOwn,
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _forwardFromTagLens(
    BuildContext context,
    ConstellationCubit cubit,
    Set<String> ownTagIds,
  ) async {
    final mine = [
      for (final request
          in cubit.state.field?.requests ?? const <ConstellationRequest>[])
        if (request.isMine &&
            BeaconStatus.fromSmallint(request.status).isOpenFamily)
          request,
    ];
    final picked = await showConstellationTagLensRequestPicker(context, mine);
    if (picked == null || !context.mounted) return;
    _exitArrangingIfActive();
    await GetIt.I<AppNavigator>().forwardBeacon(
      picked.id,
      tags: ownTagIds.isEmpty ? null : ownTagIds.join(','),
    );
  }

  /// A person node let go over a tag chip joins that tag instead of being
  /// pinned. True when the drop was taken.
  bool _dropOnTagChip(
    BuildContext context,
    ConstellationCubit cubit,
    FieldPersonNode node, {
    Offset? globalPosition,
  }) {
    final store = _peopleTags;
    final pointer = globalPosition ?? _lastPointerGlobal;
    if (store == null || pointer == null || node.person.id == cubit.viewerId) {
      return false;
    }
    final tagId =
        _lastTagChipDropHint ?? constellationTagChipDropAt(context, pointer);
    _lastTagChipDropHint = null;
    if (tagId == null) return false;
    cubit.cancelPlacement(suppressLateGestureEnd: false);
    unawaited(_addDroppedToTag(context, store, tagId, node.person.id));
    return true;
  }

  void _placeTagMagnet(PersonTag tag, [Offset? global]) {
    final cubit = context.read<ConstellationCubit>();
    final box = _graphStackKey.currentContext?.findRenderObject();
    final store = _peopleTags;
    if (box is! RenderBox ||
        store == null ||
        cubit.state.tagView != null ||
        cubit.state.isComposing ||
        !widget.peopleTagsEnabled) {
      return;
    }
    final drop = global ?? box.localToGlobal(box.size.center(Offset.zero));
    if (!(Offset.zero & box.size).contains(box.globalToLocal(drop))) return;
    final position = cubit.graphController.globalToScene(drop);
    if (position == null) return;
    cubit.placeTagMagnet(
      tagId: tag.id,
      position: position,
      tagsOfPerson: store.tagsOfPerson,
    );
  }

  Future<void> _addDroppedToTag(
    BuildContext context,
    PeopleTagsCase store,
    String tagId,
    String personId,
  ) async {
    final tag = store.tags.where((t) => t.id == tagId).firstOrNull;
    if (tag == null) return;
    final l10n = L10n.of(context)!;
    try {
      await store.applyMembership([
        PersonTagMemberOp(tagId: tagId, personId: personId, add: true),
      ]);
    } on Object catch (error) {
      if (context.mounted) {
        showSnackBar(context, text: error.toString(), isError: true);
      }
      return;
    }
    if (!context.mounted) return;
    showUndoSnackBar(
      context,
      text: l10n.peopleTagsDroppedOnChip(tag.name),
      onUndo: () => unawaited(
        store
            .applyMembership([
              PersonTagMemberOp(tagId: tagId, personId: personId, add: false),
            ])
            .catchError((Object _) {}),
      ),
    );
  }

  Widget _buildGraphStack(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state,
    SceneLayoutAlgorithm layoutAlgorithm,
    bool panelVisible,
    bool compactSheetExpanded,
  ) {
    _mountedLayoutAlgorithm = layoutAlgorithm;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _measureBottomChromeColumnHeight();
      _syncCameraViewportInsetsFromController();
    });
    final cameraInsets = _cameraViewportInsets(context, panelVisible);
    final tt = context.tt;
    final compactPanel = _compactContextPanelOpen(context, panelVisible);
    final cameraRightInset =
        panelVisible && context.windowClass != WindowClass.compact
        ? tt.screenHPadding + tt.graphPersonContextWidth + tt.screenHPadding
        : tt.screenHPadding;

    final composer = maybeConstellationComposer(context);
    void offerCreate(Offset scene) {
      final box = _graphStackKey.currentContext?.findRenderObject();
      if (composer == null || box is! RenderBox) {
        return;
      }
      unawaited(
        showConstellationCreateMenu(
          context,
          composer: composer,
          globalPosition: box.localToGlobal(
            cubit.graphController.sceneToViewportLocal(scene),
          ),
          scenePosition: scene,
        ),
      );
    }

    void onCanvasSecondary(Offset scene) {
      if (_tagHullMenuDragNodeId != null) {
        return;
      }
      if (widget.peopleTagsEnabled &&
          cubit.state.tagView == null &&
          !cubit.state.isComposing &&
          (composer == null || composer.createCubit == null)) {
        final tagId = _tagHullIdAtScene(cubit, scene);
        if (tagId != null) {
          unawaited(_showTagHullMoveMenu(cubit, tagId, scene));
          return;
        }
      }
      offerCreate(scene);
    }

    final mapSelectionCubit = maybeConstellationSelection(context);
    final mapArranging = mapSelectionCubit?.state.arranging ?? false;
    final touchNodeDragLocked =
        mapSelectionCubit != null && !mapArranging && !cubit.state.isComposing;
    bool canDragNode(NodeDetails node) {
      if (cubit.state.isComposing && !mapArranging) {
        return cubit.isComposerDrag(node);
      }
      return cubit.canDragNode(node);
    }

    cubit.applyArrangingToolbarDragCentreLimit(null);

    return Stack(
      key: _graphStackKey,
      fit: StackFit.expand,
      children: [
        // A new touch or wheel on the map cancels a running reveal pan.
        Listener(
          onPointerDown: (event) {
            _lastPointerGlobal = event.position;
            _lastTagChipDropHint = null;
            _pointersDown++;
            _fieldSettleBackTimer?.cancel();
            _fieldSettleBackTimer = null;
            _stopReveal();
            _takeMapFocus();
          },
          onPointerMove: (event) {
            _lastPointerGlobal = event.position;
            if (_tagHullMenuDragNodeId != null) {
              _tickTagHullMenuDrag(cubit, event.position);
            }
          },
          onPointerUp: (event) {
            _lastPointerGlobal = event.position;
            if (_tagHullMenuDragNodeId != null) {
              _finishTagHullMenuDrag(cubit);
            }
            _onPointerReleased();
          },
          onPointerCancel: (_) => _onPointerReleased(),
          onPointerSignal: (_) => _stopReveal(),
          // The map markers are one Tab stop with roving focus (#391, #615):
          // Tab enters on one marker, the arrow keys move between markers.
          child: FocusTraversalGroup(
            policy: _mapTraversalPolicy,
            child: GraphView<NodeDetails, EdgeDetails>(
              controller: cubit.graphController,
              canvasSize: ConstellationBody._canvasSize,
              canvasBackgroundBuilder: (context) =>
                  _buildCanvasBackground(context, cubit, composer),
              // A click on an empty spot clears the selection (#680); a pan
              // or a long press never counts as one. The Field screen always
              // provides a composer, so only a composing session turns it off.
              onCanvasTap: composer == null || composer.createCubit == null
                  ? (_) => _onEmptyMapTap(context, cubit)
                  : null,
              onCanvasSecondaryTap:
                  composer == null || composer.createCubit != null
                  ? null
                  : onCanvasSecondary,
              onCanvasLongPress:
                  composer == null || composer.createCubit != null
                  ? null
                  : offerCreate,
              // Holding empty space in a tag's hull lifts the whole tag.
              onCanvasLongPressDrag:
                  !widget.peopleTagsEnabled ||
                      composer == null ||
                      composer.createCubit != null
                  ? null
                  : (scene) => _liftTagHull(cubit, scene),
              // The hold named a member the map could not grab: no node drag
              // follows, so the lifted tag is put down here.
              onCanvasLongPressDragFailed: (_) {
                _lowerTagHull();
                cubit.onPointerCancelDuringDrag();
              },
              minScale: 0.1,
              centerOnFirstLayout: false,
              layoutAlgorithm: layoutAlgorithm,
              // New Requests spring out from under their author along this
              // transition; reduced motion lands every node at once.
              layoutTransitionDuration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : cubit.tagViewMotionActive
                  ? _tagViewTransitionDuration
                  : _layoutTransitionDuration,
              touchNodeDragLocked: touchNodeDragLocked,
              canDragNode: canDragNode,
              transformNodeDragPosition: cubit.clampClusterDragPosition,
              onNodeLongPress: mapSelectionCubit == null
                  ? null
                  : (node, position) {
                      if (cubit.state.tagView != null) {
                        return false;
                      }
                      if (!cubit.canDragNode(node)) {
                        return false;
                      }
                      if (cubit.state.isComposing) {
                        return node is FieldPersonNode &&
                            cubit.isComposerDrag(node);
                      }
                      mapSelectionCubit.enterArranging();
                      return true;
                    },
              onNodeDragStart: (node, position) {
                // The tag view only looks; a drag there writes nothing. A
                // lifted tag began its group drag when the hold lifted it.
                if (cubit.state.tagView != null || _liftedTagId != null) {
                  return;
                }
                // While composing a person is only moved for the session.
                if (node is FieldPersonNode && cubit.isComposerDrag(node)) {
                  cubit.beginComposerDrag(node);
                  return;
                }
                final target = cubit.anchorTargetForNode(node);
                if (target == null) {
                  return;
                }
                // A node of the selection takes the rest of it along; any
                // other node moves alone and the selection stays.
                final group =
                    maybeConstellationSelection(
                      context,
                    )?.state.dragGroupFor(target) ??
                    const <ConstellationAnchorTarget>{};
                if (cubit.isAnchored(target)) {
                  cubit.beginDragExisting(target: target, group: group);
                } else {
                  cubit.beginDragNew(target: target, group: group);
                }
              },
              onNodeDragUpdate: (node, position, globalPosition) {
                cubit.updateDragPresentation(
                  nodeId: node.id,
                  sceneCentre: position,
                );
                _syncComposerPersonPositions(cubit, composer);
                _lastPointerGlobal = globalPosition;
                if (_peopleTags != null &&
                    _liftedTagId == null &&
                    !cubit.state.isComposing &&
                    cubit.state.tagView == null) {
                  _lastTagChipDropHint = constellationTagChipDropAt(
                    context,
                    globalPosition,
                  );
                }
              },
              onNodeDragEnd: (node, position, globalPosition) {
                final tagLifted = _liftedTagId != null;
                _lowerTagHull();
                if (cubit.state.tagView != null) {
                  cubit.endTagViewDrag(node);
                  return;
                }
                if (node is FieldPersonNode && cubit.isComposerDragActive) {
                  cubit.endComposerDrag(node, position);
                  _syncComposerPersonPositions(cubit, composer);
                  composer?.personDropped(node.id);
                  return;
                }
                if (!tagLifted &&
                    node is FieldPersonNode &&
                    _dropOnTagChip(
                      context,
                      cubit,
                      node,
                      globalPosition: globalPosition,
                    )) {
                  return;
                }
                final target = cubit.anchorTargetForNode(node);
                if (target == null) {
                  return;
                }
                switch (cubit.state.placementPhase) {
                  case ConstellationPlacementPhase.draggingExisting:
                  case ConstellationPlacementPhase.draggingNew:
                    unawaited(
                      cubit
                          .onExistingNodeDrop(
                            target: target,
                            sceneCentre: position,
                          )
                          .then(
                            (_) => _syncComposerPersonPositions(
                              cubit,
                              composer,
                            ),
                          ),
                    );
                  case ConstellationPlacementPhase.idle:
                  case ConstellationPlacementPhase.composing:
                    break;
                }
              },
              onNodeDragCancel: (_) {
                _lowerTagHull();
                cubit.onPointerCancelDuringDrag();
                _syncComposerPersonPositions(cubit, composer);
              },
              onNodeTap: (node) => _onNodeTap(context, cubit, node),
              nodePaintOrder: cubit.orderedNodeIdsForPaint(),
              nodeTapHitTester: (scenePosition, orderedIds) {
                if (cubit.state.isComposing) {
                  final person = cubit.mapNodeAtSceneCentre(
                    scenePosition,
                    peopleOnly: true,
                  );
                  if (person is FieldPersonNode) return person.graphNodeId;
                }
                final frame = _frameHolder.frame;
                final controller = cubit.graphController;
                if (frame == null ||
                    (frame.snapshot
                                as GraphSceneSnapshot<NodeDetails, EdgeDetails>)
                            .sceneRevision !=
                        controller.sceneRevision) {
                  return null;
                }
                // A finger that lands right after the camera moved is a frame
                // ahead of the painted frame: resolve on the map it sees now.
                return resolveConstellationTap(
                  frame.cameraRevision == controller.cameraRevision.value
                      ? frame
                      : frame.recentredOn(
                          cameraRevision: controller.cameraRevision.value,
                          centreOf: (id) {
                            final scene = controller.getPositionOrNullForId(
                              id,
                            );
                            return scene == null
                                ? null
                                : controller.sceneToViewportLocal(scene);
                          },
                        ),
                  controller.sceneToViewportLocal(scenePosition),
                );
              },
              edgePainter: ConstellationEdgePainter(
                edgeKindByPair: cubit.edgeKindByPair,
                edgeFadeBySemanticId: cubit.edgeFadeBySemanticId,
                forwardTreePulseReader: () =>
                    cubit.forwardTreeEdgePulseBySemanticId,
                tt: context.tt,
                scheme: Theme.of(context).colorScheme,
                repaint: _edgeRepaint,
                cameraScale: () => cubit.graphController.cameraScale,
              ),
              nodeBuilder: (_, node) {
                final l10n = L10n.of(context)!;
                final tt = context.tt;
                final scheme = Theme.of(context).colorScheme;
                final personPinState = node is FieldPersonNode
                    ? cubit.fieldPersonById(node.person.id)?.pinState
                    : null;
                final mapNode = switch (node) {
                  FieldPersonNode(
                    :final ring,
                    :final person,
                  ) =>
                    _ConstellationMapNode(
                      detail: _detail,
                      forwardTreeMarker:
                          cubit.forwardTreeRecipientMarkerByPersonId[person.id],
                      statusBadge: personPinState != null
                          ? ExcludeSemantics(
                              child: ConstellationMarkerBadge.pinState(
                                pinState: personPinState == 'tombstone'
                                    ? 'accountDeleted'
                                    : personPinState,
                                l10n: l10n,
                                tt: tt,
                                scheme: scheme,
                              ),
                            )
                          : null,
                      dot: ring == 0
                          ? null
                          : _OverviewDotSpec(
                              sceneSize: node.size,
                              camera: cubit.graphController.cameraRevision,
                              scale: () => cubit.graphController.cameraScale,
                            ),
                      districtPerson: ring == 0 ? null : person,
                      temporaryOutline:
                          cubit.forwardTreeTemporaryOutlinePersonIds.contains(
                                person.id,
                              ) ||
                              (widget.fieldMembershipV2Enabled &&
                                  cubit
                                          .fieldPersonById(person.id)
                                          ?.fieldMembership ==
                                      ConstellationFieldMembership.temporary)
                          ? ConstellationTemporaryOutline(
                              key: TestIds.key(
                                TestIds.constellationTemporaryOutline(
                                  person.id,
                                ),
                              ),
                              color: tt.graphEdgePath,
                              dash: tt.tightGap * 1.5,
                              gap: tt.tightGap,
                              strokeWidth: tt.tightGap / 2,
                            )
                          : null,
                      child: GraphNodeWidget(
                        key: TestIds.key(TestIds.graphNode(node.id)),
                        nodeDetails: node,
                        hiddenNeighborCount: cubit
                            .forwardTreeAnonymousCountByPersonId[person.id],
                        isOrigin: ring == 0,
                        isFocused:
                            panelVisible && node.id == state.selectedPersonId,
                      ),
                    ),
                  FieldBeaconNode(request: final request?) =>
                    _ConstellationMapNode(
                      detail: _detail,
                      temporaryOutline:
                          cubit.isSearchTemporaryOutlineBeacon(request.id)
                          ? ConstellationTemporaryOutline(
                              key: TestIds.key(
                                TestIds.constellationTemporaryOutline(
                                  request.id,
                                ),
                              ),
                              color: tt.graphEdgePath,
                              dash: tt.tightGap * 1.5,
                              gap: tt.tightGap,
                              strokeWidth: tt.tightGap / 2,
                            )
                          : null,
                      statusBadge: request.isPlaceholder
                          ? ExcludeSemantics(
                              child: ConstellationMarkerBadge.pinState(
                                pinState: request.pinState,
                                l10n: l10n,
                                tt: tt,
                                scheme: scheme,
                              ),
                            )
                          : constellationRequestStatusPresentation(
                                  rawStatus: request.status,
                                  l10n: l10n,
                                  tt: tt,
                                ) ==
                                null
                          ? null
                          : ExcludeSemantics(
                              child: ConstellationMarkerBadge.status(
                                rawStatus: request.status,
                                l10n: l10n,
                                tt: tt,
                                scheme: scheme,
                              ),
                            ),
                      child: GraphNodeWidget(
                        key: TestIds.key(TestIds.graphNode(node.id)),
                        nodeDetails: node,
                        isFocused: state.selectedRequestId == request.id,
                      ),
                    ),
                  FieldBeaconNode(post: final post?) => _ConstellationMapNode(
                    detail: _detail,
                    temporaryOutline:
                        cubit.isSearchTemporaryOutlineBeacon(post.id)
                        ? ConstellationTemporaryOutline(
                            key: TestIds.key(
                              TestIds.constellationTemporaryOutline(post.id),
                            ),
                            color: tt.graphEdgePath,
                            dash: tt.tightGap * 1.5,
                            gap: tt.tightGap,
                            strokeWidth: tt.tightGap / 2,
                          )
                        : null,
                    child: GraphNodeWidget(
                      key: TestIds.key(TestIds.graphNode(node.id)),
                      nodeDetails: node,
                      isFocused: state.selectedRequestId == post.id,
                    ),
                  ),
                  _ => const SizedBox.shrink(),
                };
                if (mapNode is! _ConstellationMapNode) {
                  return mapNode;
                }
                // The semantics label changes only with the pin state, so a
                // move or a phase change leaves the node subtree alone.
                final anchorTarget = cubit.anchorTargetForNode(node);
                Widget build(
                  List<PersonTag> ownTags,
                ) => BlocSelector<ConstellationCubit, ConstellationState, bool>(
                  bloc: cubit,
                  selector: (_) =>
                      anchorTarget != null && cubit.isAnchored(anchorTarget),
                  builder: (context, _) => ConstellationPersonPresenceBuilder(
                    personId: node is FieldPersonNode ? node.person.id : null,
                    builder: (context, online) => _wrapFieldBeaconMapChrome(
                      node,
                      _wrapConstellationMapNodeSemantics(
                        context: context,
                        cubit: cubit,
                        state: state,
                        node: node,
                        panelVisible: panelVisible,
                        mapNode: mapNode.withOwnTags(ownTags),
                        online: online,
                        ownTags: ownTags,
                      ),
                    ),
                  ),
                );
                final store = _peopleTags;
                if (store == null || node is! FieldPersonNode) {
                  return build(const []);
                }
                return StreamBuilder<void>(
                  stream: store.changes,
                  builder: (_, _) => build(_ownTagsOf(store, node.person.id)),
                );
              },
            ),
          ),
        ),
        Positioned.fill(
          child: RepositoryProvider<ConstellationZoomLevelController>.value(
            value: _zoom,
            child: ConstellationViewportOverlay(
              cubit: cubit,
              frameHolder: _frameHolder,
              peopleTags: _peopleTags,
            ),
          ),
        ),
        Positioned.fill(
          child: ConstellationSelectionLayers(
            cubit: cubit,
            hitsNode: (local) => _hitsMapNode(cubit, local),
          ),
        ),
        if (widget.peopleTagsEnabled &&
            state.tagView == null &&
            !state.isComposing)
          Positioned.fill(
            child: ConstellationTagMagnetLayer(
              cubit: cubit,
              tags: _peopleTags?.tags ?? const [],
              frameHolder: _frameHolder,
            ),
          ),
        // The handle paints before the sheet below, so panning the circle
        // under the sheet does not draw the handle on top of it.
        if (composer != null)
          Positioned.fill(
            child: ConstellationComposerHandle(
              composer: composer,
              controller: cubit.graphController,
              hitsPerson: (point) =>
                  cubit.mapNodeAtSceneCentre(point, peopleOnly: true)
                      is FieldPersonNode,
            ),
          ),
        if (composer != null)
          BlocBuilder<ConstellationComposerCubit, RadiusRecipientSelection>(
            bloc: composer,
            builder: (context, _) => composer.createCubit == null
                ? const SizedBox.shrink()
                : Positioned.fill(
                    child: ConstellationComposerSheet(
                      composer: composer,
                      onOpenFullForm: (open) => unawaited(() async {
                        await open(GetIt.I<AppNavigator>());
                        if (context.mounted) await cubit.load();
                      }()),
                    ),
                  ),
          ),
        Positioned.fill(
          child: ConstellationPlacementMarkerLayer(cubit: cubit),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearPiActive.builder(
            context,
            state.status is StateIsLoading,
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            left: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                top: tt.rowGap,
                right: cameraRightInset,
              ),
              child: compactPanel && compactSheetExpanded
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (state.forwardTreeOverlay != null)
                          Padding(
                            padding: EdgeInsets.only(bottom: tt.tightGap),
                            child: ConstellationForwardTreeOverlayBar(
                              cubit: cubit,
                            ),
                          ),
                        ConstellationCameraControls(
                          cubit: cubit,
                          viewportInsets: cameraInsets,
                          arrangeV2Enabled: widget.arrangeV2Enabled,
                        ),
                      ],
                    ),
            ),
          ),
        ),
        if (_detail != ConstellationDetailLevel.close &&
            !(panelVisible && context.windowClass == WindowClass.compact))
          Positioned(
            right: cameraRightInset,
            bottom: 0,
            child: SafeArea(
              left: false,
              top: false,
              child: Padding(
                padding: EdgeInsets.all(tt.rowGap),
                child: ConstellationMinimap(
                  controller: cubit.graphController,
                  viewerGraphId: 'fp:${cubit.viewerId}',
                  expanded: _minimapExpanded,
                ),
              ),
            ),
          ),
        if (widget.legendExpanded &&
            !state.isComposing &&
            !(compactPanel && compactSheetExpanded))
          Positioned(
            left: 0,
            bottom: compactPanel ? null : 0,
            top: compactPanel ? 0 : null,
            child: SafeArea(
              top: compactPanel,
              bottom: !compactPanel,
              right: false,
              child: Padding(
                padding: EdgeInsets.all(tt.rowGap),
                child: _buildLegendPanel(
                  context,
                  panelVisible: panelVisible,
                  compactSheetHeight: _compactSheetHeight,
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          top: compactPanel ? 0 : null,
          bottom: compactPanel ? null : 0,
          child: SafeArea(
            child: KeyedSubtree(
              key: _bottomChromeColumnKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compactPanel) _buildTagLensPanel(context, cubit),
                  ConstellationSelectionBar(
                    cubit: cubit,
                    peopleTagsEnabled: widget.peopleTagsEnabled,
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: cameraRightInset + tt.buttonHeight + tt.rowGap,
          bottom: 0,
          child: SafeArea(
            top: false,
            left: false,
            child: _ConstellationFieldHoldHintBanner(cubit: cubit),
          ),
        ),
        if (mapSelectionCubit != null)
          Positioned(
            left: 0,
            right: cameraRightInset + tt.buttonHeight + tt.rowGap,
            bottom: 0,
            child:
                BlocBuilder<
                  ConstellationSelectionCubit,
                  ConstellationMultiSelection
                >(
                  bloc: mapSelectionCubit,
                  buildWhen: (previous, current) =>
                      previous.arranging != current.arranging,
                  builder: (context, selectionState) {
                    if (!selectionState.arranging) {
                      return const SizedBox.shrink();
                    }
                    return SafeArea(
                      top: false,
                      left: false,
                      child: Padding(
                        padding: EdgeInsets.all(tt.tightGap),
                        child: ListenableBuilder(
                          listenable: RendererBinding.instance.mouseTracker,
                          builder: (context, _) {
                            final mouse = RendererBinding
                                .instance
                                .mouseTracker
                                .mouseIsConnected;
                            final l10n = L10n.of(context)!;
                            return Text(
                              mouse
                                  ? l10n.constellationArrangingHintMouse
                                  : l10n.constellationArrangingHintTouch,
                              key: const Key('constellation.arranging.hint'),
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
          ),
        if (panelVisible && state.viewMode == ConstellationViewMode.map)
          _buildContextOverlay(
            context,
            cubit,
            state,
            mapStackHeight: _effectiveMapStackHeight,
          ),
      ],
    );
  }

  /// The viewer's tag store; null where none is registered.
  final PeopleTagsCase? _peopleTags = GetIt.I.isRegistered<PeopleTagsCase>()
      ? GetIt.I<PeopleTagsCase>()
      : null;

  /// Own tags on [personId], in tag order.
  List<PersonTag> _ownTagsOf(PeopleTagsCase store, String personId) {
    final ids = store.tagsOfPerson(personId);
    return [
      for (final tag in store.tags)
        if (ids.contains(tag.id)) tag,
    ];
  }

  ConstellationTagLens? _tagLens;

  /// One lens per filter and field snapshot, shared by every marker.
  ConstellationTagLens _tagLensFor(
    ConstellationCubit cubit,
    ConstellationTagLensCubit lensCubit,
    ConstellationTagFilter filter,
  ) {
    final people = cubit.state.field?.peers ?? const <ConstellationPerson>[];
    final cached = _tagLens;
    if (cached != null &&
        cached.filter == filter &&
        identical(_tagLensPeople, people)) {
      return cached;
    }
    _tagLensPeople = people;
    return _tagLens = ConstellationTagLens(
      filter: filter,
      people: people,
      ownTagIdsOf: lensCubit.ownTagIdsOf,
      viewerId: cubit.viewerId,
    );
  }

  List<ConstellationPerson>? _tagLensPeople;

  Widget _wrapConstellationMapNodeSemantics({
    required BuildContext context,
    required ConstellationCubit cubit,
    required ConstellationState state,
    required NodeDetails node,
    required bool panelVisible,
    required _ConstellationMapNode mapNode,
    bool online = false,
    List<PersonTag> ownTags = const [],
  }) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final isEgo = switch (node) {
      FieldPersonNode(:final person) => person.id == cubit.viewerId,
      _ => false,
    };
    final selected = switch (node) {
      FieldPersonNode() => panelVisible && node.id == state.selectedPersonId,
      FieldBeaconNode(request: final request?) =>
        state.selectedRequestId == request.id,
      FieldBeaconNode(post: final post?) => state.selectedRequestId == post.id,
      _ => false,
    };
    final label = constellationNodeSemanticLabel(
      l10n: l10n,
      tt: tt,
      cubit: cubit,
      node: node,
      online: online,
      ownTagNames: [for (final tag in ownTags) tag.name],
      unreadAuthorRollup: () {
        final field = cubit.state.field;
        final frame = _frameHolder.frame;
        if (field == null || frame == null) {
          return false;
        }
        if (node case FieldPersonNode(:final person)) {
          final glow = constellationFieldUnreadGlowGraphIds(
            field: field,
            beaconGraphIdsOnMap: {
              for (final id in frame.bodies.keys)
                if (id.startsWith(kConstellationFieldBeaconGraphPrefix)) id,
            },
            personGraphIdsOnMap: {
              for (final id in frame.bodies.keys)
                if (id.startsWith(kConstellationFieldPersonGraphPrefix)) id,
            },
          );
          return glow.containsKey(
            constellationFieldPersonGraphId(person.id),
          );
        }
        return false;
      }(),
    );
    // Off the selected person's trust chain (#641) or forward-tree overlay (#774):
    // the marker fades.
    final chainMarker =
        cubit.isDimmedByTrustChain(node) || cubit.isDimmedByForwardTree(node)
        ? Opacity(opacity: kConstellationTrustChainDimOpacity, child: mapNode)
        : mapNode;
    // Outside the tag selection: the marker fades; positions stay put.
    final lensCubit = maybeConstellationTagLens(context);
    final marker = lensCubit == null
        ? chainMarker
        : BlocBuilder<ConstellationTagLensCubit, ConstellationTagFilter>(
            bloc: lensCubit,
            builder: (_, filter) =>
                _tagLensFor(cubit, lensCubit, filter).isNodeDimmed(node)
                ? Opacity(
                    opacity: kConstellationTagLensDimOpacity,
                    child: chainMarker,
                  )
                : chainMarker,
          );
    if (isEgo) {
      return Semantics(
        selected: selected,
        label: label,
        child: ExcludeSemantics(child: marker),
      );
    }
    // One node per marker (#391): the marker's focus semantics (focusable /
    // focused / focus action) merge into this labelled button, so Tab and the
    // web engine's tabindex land on it, and Enter/Space (ActivateIntent, and
    // ButtonActivateIntent for Enter on web) do what a tap does. Focus alone
    // does not select.
    return _MinExtentSemantics(
      identifier: '$_mapNodeSemanticsPrefix${node.graphNodeId}',
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: () => _onNodeTap(context, cubit, node),
      neighbourOffsets: () => _neighbourOffsets(node.graphNodeId),
      child: _ConstellationMapNodeFocus(
        circle: node is FieldPersonNode,
        onActivate: () => _onNodeTap(context, cubit, node),
        onKeyboardFocus: () => _revealFocusedNode(cubit, node),
        child: ExcludeSemantics(child: marker),
      ),
    );
  }

  /// Screen offsets from the centre of [id] to the centres of the other
  /// nodes on the map, as the last presentation frame drew them.
  List<Offset> _neighbourOffsets(GraphNodeId id) {
    final bodies = _frameHolder.frame?.bodies;
    final own = bodies?[id]?.center;
    if (bodies == null || own == null) {
      return const [];
    }
    return [
      for (final entry in bodies.entries)
        if (entry.key != id) entry.value.center - own,
    ];
  }

  /// A marker Tab (or a screen reader) moved focus onto is panned into view
  /// clear of the panel open now (#391, the #458 reveal); it is not selected.
  void _revealFocusedNode(ConstellationCubit cubit, NodeDetails node) {
    if (!mounted) {
      return;
    }
    final state = cubit.state;
    _revealNode(
      context,
      cubit,
      node,
      contextPanelVisible:
          state.selectedPersonId != null || state.selectedRequestId != null,
    );
  }

  Widget _buildLegendPanel(
    BuildContext context, {
    required bool panelVisible,
    double compactSheetHeight = 0,
  }) {
    final tt = context.tt;
    final legend = GraphLegendPanel(
      mode: GraphLegendMode.constellation,
      expanded: true,
      onToggle: widget.onToggleLegend,
    );
    if (!panelVisible || context.windowClass != WindowClass.compact) {
      return legend;
    }
    final peek = _effectiveMapStackHeight > 0
        ? _effectiveMapStackHeight * tt.fieldSheetPeekFraction
        : compactSheetHeight;
    final sheet = compactSheetHeight > 0 ? compactSheetHeight : peek;
    final media = MediaQuery.of(context);
    final freeBelowPanel =
        _effectiveMapStackHeight - sheet - media.padding.top - tt.rowGap * 2;
    final capHeight =
        media.size.height * tt.graphLegendMaxHeightFractionCompact;
    final maxHeight = math.min(
      capHeight,
      freeBelowPanel < 0 ? 0.0 : freeBelowPanel,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: legend),
    );
  }
}

/// [Semantics] whose node rect is at least [kMinInteractiveDimension] on
/// screen at any zoom (#678), like the tap target (#640), so touch
/// exploration finds the node where a tap does. Where the enlarged rects of
/// neighbouring nodes would cross the line halfway between two centres, the
/// rect shrinks to its own side, so a click through the semantics tree only
/// ever reaches the nearest node; a click between the rects reaches the map
/// as pointer events, which resolve to the nearest node too (#640).
class _MinExtentSemantics extends Semantics {
  // Not const: Semantics has no const constructor taking these flags.
  _MinExtentSemantics({
    required this.neighbourOffsets,
    super.identifier,
    super.container,
    super.button,
    super.selected,
    super.label,
    super.onTap,
    super.child,
  });

  /// Screen offsets from this node's centre to the other nodes' centres.
  final List<Offset> Function() neighbourOffsets;

  @override
  RenderSemanticsAnnotations createRenderObject(BuildContext context) =>
      _RenderMinExtentSemantics(
        container: container,
        explicitChildNodes: explicitChildNodes,
        excludeSemantics: excludeSemantics,
        blockUserActions: blockUserActions,
        properties: properties,
        localeForSubtree: localeForSubtree,
        textDirection:
            properties.textDirection ?? Directionality.maybeOf(context),
        neighbourOffsets: neighbourOffsets,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMinExtentSemantics renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    renderObject.neighbourOffsets = neighbourOffsets;
  }
}

/// Half the side (screen px) of the smallest area Chrome adjusts a touch
/// over (`kMinAdjustmentSizeDip`, 20 px), on the web build where map
/// markers are clickable semantics elements.
const _kBrowserTouchAreaHalfSide = 10.0;

class _RenderMinExtentSemantics extends RenderSemanticsAnnotations {
  _RenderMinExtentSemantics({
    required this.neighbourOffsets,
    required super.properties,
    super.container,
    super.explicitChildNodes,
    super.excludeSemantics,
    super.blockUserActions,
    super.localeForSubtree,
    super.textDirection,
  });

  List<Offset> Function() neighbourOffsets;

  @override
  Rect get semanticBounds {
    final bounds = super.semanticBounds;
    if (!attached) {
      return bounds;
    }
    // Screen pixels per local pixel (the camera zoom); semantics geometry is
    // recomputed whenever the camera transform changes.
    final m = getTransformTo(null).storage;
    final scale = math.sqrt(m[0] * m[0] + m[1] * m[1]);
    if (scale <= 0 || !scale.isFinite) {
      return bounds;
    }
    final minExtent = kMinInteractiveDimension / scale;
    if (bounds.width >= minExtent && bounds.height >= minExtent) {
      return bounds;
    }
    // Extents from the centre: left, right, up, down.
    var left = math.max(bounds.width, minExtent) / 2;
    var right = left;
    var up = math.max(bounds.height, minExtent) / 2;
    var down = up;
    // Keep the rect on this node's side of the line halfway to each
    // neighbour's centre: the corner nearest that neighbour may not cross it.
    // The axis the neighbour lies mostly along gives way first, down to a
    // quarter of the distance; then the other axis does too.
    final neighbours = neighbourOffsets();
    for (final offset in neighbours) {
      final dx = offset.dx / scale;
      final dy = offset.dy / scale;
      // A neighbour a whole target away along either axis never reaches into
      // this rect with its own round target, so the tap hit test never picks
      // it here either.
      if (dx.abs() >= minExtent || dy.abs() >= minExtent) {
        continue;
      }
      final xMajor = dx.abs() >= dy.abs();
      final major = xMajor ? dx.abs() : dy.abs();
      final minor = xMajor ? dy.abs() : dx.abs();
      if (major == 0) {
        continue;
      }
      double majorExtent() =>
          xMajor ? (dx > 0 ? right : left) : (dy > 0 ? down : up);
      double minorExtent() =>
          xMajor ? (dy > 0 ? down : up) : (dx > 0 ? right : left);
      final half = (major * major + minor * minor) / 2;
      if (major * majorExtent() + minor * minorExtent() <= half) {
        continue;
      }
      var minorCap = minorExtent();
      if (minor > 0) {
        minorCap = math.min(minorCap, (half - major * major / 4) / minor);
      }
      final majorCap = math.min(
        majorExtent(),
        (half - minor * minorCap) / major,
      );
      if (xMajor) {
        if (dx > 0) {
          right = majorCap;
        } else {
          left = majorCap;
        }
        if (dy > 0) {
          down = minorCap;
        } else if (dy < 0) {
          up = minorCap;
        }
      } else {
        if (dy > 0) {
          down = majorCap;
        } else {
          up = majorCap;
        }
        if (dx > 0) {
          right = minorCap;
        } else if (dx < 0) {
          left = minorCap;
        }
      }
    }
    // An axis cut to less than half a browser's touch area is centred on the
    // node: its longer side gives way as far as the shorter one. A browser's
    // touch adjustment sends a finger to the clickable box its touch area
    // covers best, and a box that runs on past the node on one side loses
    // that to a small neighbour's box, even under the finger (#640).
    final halfTouchArea = _kBrowserTouchAreaHalfSide / scale;
    if (math.min(left, right) < halfTouchArea) {
      left = right = math.min(left, right);
    }
    if (math.min(up, down) < halfTouchArea) {
      up = down = math.min(up, down);
    }
    final c = bounds.center;
    // Chrome expands clickable boxes to whole CSS pixels. Where a bisector
    // runs along a shared edge, round that axis inward if it still includes
    // the dot centre, so the boxes do not overlap again after expansion.
    final screenCentre = localToGlobal(c);
    if (neighbours.any(
      (p) => p.dy == 0 && p.dx.abs() / scale <= left + right,
    )) {
      final start = (screenCentre.dx - left * scale).ceilToDouble();
      final end = (screenCentre.dx + right * scale).floorToDouble();
      if (start <= screenCentre.dx && screenCentre.dx < end) {
        left = (screenCentre.dx - start) / scale;
        right = (end - screenCentre.dx) / scale;
      }
    }
    if (neighbours.any((p) => p.dx == 0 && p.dy.abs() / scale <= up + down)) {
      final start = (screenCentre.dy - up * scale).ceilToDouble();
      final end = (screenCentre.dy + down * scale).floorToDouble();
      if (start <= screenCentre.dy && screenCentre.dy < end) {
        up = (screenCentre.dy - start) / scale;
        down = (end - screenCentre.dy) / scale;
      }
    }
    return Rect.fromLTRB(c.dx - left, c.dy - up, c.dx + right, c.dy + down);
  }
}

/// A map marker's focus node, so the arrow keys pick among markers only and
/// never land on the map's own focus node or a panel (#615).
class _MapMarkerFocusNode extends FocusNode {
  _MapMarkerFocusNode() : super(debugLabel: 'ConstellationMapNode');
}

class _MapArrowIntent extends Intent {
  const _MapArrowIntent(this.direction);

  final TraversalDirection direction;
}

/// Index of the point in [candidates] that an arrow key in [direction] from
/// [from] should reach, or null when nothing lies that way (#615).
///
/// Points inside the 45° cone of the arrow win over points outside it; among
/// them the score is the distance along the arrow plus twice the sideways
/// offset, so a marker straight ahead beats a closer one far to the side.
@visibleForTesting
int? nearestMapMarkerInDirection({
  required Offset from,
  required List<Offset> candidates,
  required TraversalDirection direction,
}) {
  int? best;
  var bestInCone = false;
  var bestScore = double.infinity;
  for (var i = 0; i < candidates.length; i++) {
    final delta = candidates[i] - from;
    final (along, side) = switch (direction) {
      TraversalDirection.up => (-delta.dy, delta.dx.abs()),
      TraversalDirection.down => (delta.dy, delta.dx.abs()),
      TraversalDirection.left => (-delta.dx, delta.dy.abs()),
      TraversalDirection.right => (delta.dx, delta.dy.abs()),
    };
    if (along <= 0.5) continue;
    final inCone = side <= along;
    final score = along + 2 * side;
    if ((inCone && !bestInCone) ||
        (inCone == bestInCone && score < bestScore)) {
      best = i;
      bestInCone = inCone;
      bestScore = score;
    }
  }
  return best;
}

/// Keyboard focus and activation for a map marker, with a focus ring drawn
/// around the marker while it holds keyboard focus.
class _ConstellationMapNodeFocus extends StatefulWidget {
  const _ConstellationMapNodeFocus({
    required this.child,
    required this.circle,
    required this.onActivate,
    required this.onKeyboardFocus,
  });

  final Widget child;
  final bool circle;
  final VoidCallback onActivate;

  /// Focus arrived from the keyboard or a screen reader (not a pointer).
  final VoidCallback onKeyboardFocus;

  @override
  State<_ConstellationMapNodeFocus> createState() =>
      _ConstellationMapNodeFocusState();
}

class _ConstellationMapNodeFocusState
    extends State<_ConstellationMapNodeFocus> {
  final _focusNode = _MapMarkerFocusNode();

  /// The arrow keys move focus to the nearest marker that way (#615). They
  /// sit on the marker itself, so they only act while a marker has focus,
  /// and they win over the web's arrow-to-scroll shortcuts above.
  static const _arrowShortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowUp): _MapArrowIntent(
      TraversalDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): _MapArrowIntent(
      TraversalDirection.down,
    ),
    SingleActivator(LogicalKeyboardKey.arrowLeft): _MapArrowIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): _MapArrowIntent(
      TraversalDirection.right,
    ),
  };

  void _moveFocus(TraversalDirection direction) {
    final from = _focusNode.rect.center;
    final candidates = [
      for (final node
          in _focusNode.nearestScope?.traversalDescendants ??
              const <FocusNode>[])
        if (node is _MapMarkerFocusNode && node != _focusNode) node,
    ];
    final index = nearestMapMarkerInDirection(
      from: from,
      candidates: [for (final node in candidates) node.rect.center],
      direction: direction,
    );
    if (index != null) candidates[index].requestFocus();
  }

  bool _highlight = false;

  /// The map's traversal policy this marker made its Tab stop, if any.
  _ConstellationMapReadingOrderPolicy? _rovingPolicy;

  /// Makes this marker the map's one Tab stop (#615), without taking focus.
  void _becomeTabStop() {
    final policy = FocusTraversalGroup.maybeOfNode(_focusNode);
    if (policy is _ConstellationMapReadingOrderPolicy) {
      policy.tabStop = _focusNode;
      _rovingPolicy = policy;
    }
  }

  @override
  void dispose() {
    _rovingPolicy?.forgetTabStop(_focusNode);
    _focusNode.dispose();
    super.dispose();
  }

  // Semantic focus (the web engine's Tab, a screen reader) applies the focus
  // change at once, so the focused flag is rebuilt into the same semantics
  // update instead of waiting for an unrelated frame.
  void _focusFromSemantics() {
    _semanticFocus = true;
    try {
      _focusNode.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
    } finally {
      _semanticFocus = false;
    }
  }

  bool _semanticFocus = false;

  void _onFocusChange(bool focused) {
    setState(() {});
    // Roving Tab stop (#615): whatever brought focus here (an arrow key,
    // Tab, a screen reader), this marker is now the map's one stop.
    if (focused) _becomeTabStop();
    if (focused &&
        (_semanticFocus ||
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional)) {
      widget.onKeyboardFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(
      color: Theme.of(context).colorScheme.primary,
      width: TenturaSpacing.focusRing,
      strokeAlign: BorderSide.strokeAlignOutside,
    );
    final detector = FocusableActionDetector(
      focusNode: _focusNode,
      includeFocusSemantics: false,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: _onFocusChange,
      onShowFocusHighlight: (value) {
        if (value != _highlight) setState(() => _highlight = value);
      },
      shortcuts: _arrowShortcuts,
      // Space maps to ActivateIntent everywhere, but on web Enter and
      // numpad Enter map to ButtonActivateIntent (WidgetsApp's web
      // shortcuts), so the marker answers both (#391).
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
        _MapArrowIntent: CallbackAction<_MapArrowIntent>(
          onInvoke: (intent) {
            _moveFocus(intent.direction);
            return null;
          },
        ),
      },
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: _highlight
            ? ShapeDecoration(
                shape: widget.circle
                    ? CircleBorder(side: side)
                    : RoundedRectangleBorder(
                        side: side,
                        borderRadius: BorderRadius.circular(
                          context.tt.buttonRadius,
                        ),
                      ),
              )
            : const BoxDecoration(),
        child: widget.child,
      ),
    );
    // Every marker stays focusable in semantics, so a screen reader reaches
    // each one (#615). Flutter web gives focusable semantics nodes DOM
    // tabIndex=0, but Flutter handles Tab itself as NextFocusIntent (and
    // prevents the browser default), so for keyboard users the map is still
    // one roving Tab stop (as long as the framework handles the key).
    return Semantics(
      focusable: true,
      focused: _focusNode.hasPrimaryFocus,
      onFocus: defaultTargetPlatform == TargetPlatform.iOS
          ? null
          : _focusFromSemantics,
      // The marker draws its own keyboard ring (#391); skip the app-level one.
      // A press makes the marker the Tab stop without taking focus (WAI-ARIA
      // roving tabindex, #615), so the next Tab onto the map lands here.
      child: TenturaFocusRing.exclude(
        child: Listener(
          onPointerDown: (_) => _becomeTabStop(),
          child: detector,
        ),
      ),
    );
  }
}

@immutable
class _OverviewDotSpec {
  const _OverviewDotSpec({
    required this.sceneSize,
    required this.camera,
    required this.scale,
  });

  final double sceneSize;
  final Listenable camera;
  final double Function() scale;
}

/// A [kConstellationOverviewDotDiameter] dot on screen whatever the camera
/// scale, centred in the node's own scene box.
class _OverviewDot extends StatelessWidget {
  const _OverviewDot({required this.spec, required this.color, super.key});

  final _OverviewDotSpec spec;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: spec.sceneSize,
    child: Center(
      child: ListenableBuilder(
        listenable: spec.camera,
        builder: (_, _) => SizedBox.square(
          dimension: kConstellationOverviewDotDiameter / spec.scale(),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    ),
  );
}

/// A [kConstellationDistrictMarkerDiameter] avatar on screen whatever the camera
/// scale — the same [TenturaAvatar] image path as the close level and ego,
/// with initials only while loading or when the person has no photo, centred
/// in the node's own scene box.
///
/// Counter-scale paint with the camera so the marker stays 20 pt on screen and
/// avoids per-frame text layout during zoom (#808).
class _DistrictMarker extends StatelessWidget {
  const _DistrictMarker({
    required this.spec,
    required this.person,
    required this.markerKey,
  });

  final _OverviewDotSpec spec;
  final Profile person;
  final Key? markerKey;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: spec.sceneSize,
    child: Center(
      child: ListenableBuilder(
        listenable: spec.camera,
        builder: (_, child) => Transform.scale(
          scale: 1 / spec.scale(),
          child: child,
        ),
        child: SizedBox.square(
          key: markerKey,
          dimension: kConstellationDistrictMarkerDiameter,
          child: ClipOval(
            child: TenturaAvatar(
              profile: person,
              size: kConstellationDistrictMarkerDiameter,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ConstellationMapNode extends StatelessWidget {
  const _ConstellationMapNode({
    required this.child,
    required this.detail,
    this.dot,
    this.districtPerson,
    this.temporaryOutline,
    this.forwardTreeMarker,
    this.statusBadge,
    this.ownTags = const [],
  });

  final Widget child;
  final ConstellationDetailLevel detail;

  /// Set for a person who is drawn as a bare dot at the overview.
  final _OverviewDotSpec? dot;

  /// Set for a person who is drawn as an initials circle at the district.
  final Profile? districtPerson;

  /// Dashed ring of a temporary person, drawn over the node (not at the
  /// overview, where the node is a dot).
  final Widget? temporaryOutline;

  /// Small glyph for forward-tree recipient state (#774).
  final ConstellationForwardTreeRecipientMarker? forwardTreeMarker;
  final Widget? statusBadge;
  final List<PersonTag> ownTags;

  _ConstellationMapNode withOwnTags(List<PersonTag> ownTags) =>
      _ConstellationMapNode(
        detail: detail,
        dot: dot,
        districtPerson: districtPerson,
        temporaryOutline: temporaryOutline,
        forwardTreeMarker: forwardTreeMarker,
        statusBadge: statusBadge,
        ownTags: ownTags,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    final dot = this.dot;
    final districtPerson = this.districtPerson;
    final shown = dot != null && detail == ConstellationDetailLevel.overview
        ? _OverviewDot(
            key: child.key,
            spec: dot,
            color: ownTags.isEmpty
                ? HSLColor.fromColor(tt.textMuted).withSaturation(0).toColor()
                : context.tagColors.swatchFor(ownTags.first.color).accent,
          )
        : dot != null &&
              districtPerson != null &&
              detail == ConstellationDetailLevel.district
        ? _DistrictMarker(
            spec: dot,
            person: districtPerson,
            markerKey: child.key,
          )
        : child;
    final overhang = constellationMarkerBadgeOverhang(tt);
    final statusBadge = this.statusBadge;
    final markerChar = switch (forwardTreeMarker) {
      ConstellationForwardTreeRecipientMarker.helped => '✓',
      ConstellationForwardTreeRecipientMarker.offered => '✋',
      ConstellationForwardTreeRecipientMarker.cantHelp => '✕',
      ConstellationForwardTreeRecipientMarker.opened => '·',
      ConstellationForwardTreeRecipientMarker.notOpened => '○',
      null => null,
    };
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        shown,
        if (temporaryOutline != null && identical(shown, child))
          Positioned.fill(child: temporaryOutline!),
        if (markerChar != null &&
            detail == ConstellationDetailLevel.close &&
            identical(shown, child))
          PositionedDirectional(
            bottom: -overhang,
            end: -overhang,
            child: ExcludeSemantics(
              child: Text(
                markerChar,
                style: TenturaText.labelMedium(
                  theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        if (statusBadge != null)
          PositionedDirectional(
            top: -overhang,
            start: -overhang,
            child: statusBadge,
          ),
      ],
    );
  }
}

typedef _EdgeDashPath = ({
  Offset a,
  Offset b,
  double dash,
  double gap,
  Path? path,
});

@immutable
class ConstellationEdgePainter
    implements RepaintingEdgePainter<NodeDetails, EdgeDetails> {
  ConstellationEdgePainter({
    required this.edgeKindByPair,
    required this.tt,
    required this.scheme,
    required this.repaint,
    required this.cameraScale,
    this.edgeFadeBySemanticId = const {},
    this.forwardTreePulseReader,
  });

  final Map<String, ConstellationEdgeKind> edgeKindByPair;
  final Map<String, double> edgeFadeBySemanticId;

  /// Stable reader for pulse map (equality ignores the closure identity).
  final Map<String, double> Function()? forwardTreePulseReader;
  final TenturaTokens tt;
  final ColorScheme scheme;
  @override
  final Listenable repaint;
  final double Function() cameraScale;

  /// Dash geometry per edge, rebuilt only when the edge's trimmed endpoints or
  /// dash pattern change (a drag moves a few edges per frame, not all).
  final _dashPaths = <String, _EdgeDashPath>{};

  // Painting depends only on these inputs (and the scene), so equal painters
  // paint identically and the render layer can skip redundant repaints.
  // Theme objects are rebuilt without value equality, so compare the colours
  // constellationEdgeStyle reads.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConstellationEdgePainter &&
          repaint == other.repaint &&
          tt.graphEdgePath == other.tt.graphEdgePath &&
          scheme.tertiary == other.scheme.tertiary &&
          scheme.secondary == other.scheme.secondary &&
          scheme.primary == other.scheme.primary &&
          (identical(edgeKindByPair, other.edgeKindByPair) ||
              mapEquals(edgeKindByPair, other.edgeKindByPair)) &&
          (identical(edgeFadeBySemanticId, other.edgeFadeBySemanticId) ||
              mapEquals(edgeFadeBySemanticId, other.edgeFadeBySemanticId));

  @override
  int get hashCode => Object.hash(
    repaint,
    tt.graphEdgePath,
    scheme.tertiary,
    scheme.secondary,
    scheme.primary,
  );

  @visibleForTesting
  static double effectiveWidth(double width, double cameraScale) {
    final k = cameraScale < 1 ? 1 / cameraScale : 1.0;
    return width * k;
  }

  @override
  void paint(
    Canvas canvas,
    EdgeDetails edge,
    Offset src,
    Offset dst,
  ) {
    final kind = edgeKindByPair[edge.semanticId];
    if (kind == null) {
      return;
    }

    final style = constellationEdgeStyle(kind, tt, scheme);
    final scale = cameraScale();
    final strokeWidth = effectiveWidth(style.width, scale);
    final dashLength = style.dash == 0
        ? 0.0
        : effectiveWidth(style.dash, scale);
    final dashGap = style.gap == 0 ? 0.0 : effectiveWidth(style.gap, scale);

    final sourceRadius = edge.source.size / 2;
    final destinationRadius = edge.destination.size / 2;
    final trimmed = _trim(
      src: src,
      dst: dst,
      srcInset: sourceRadius + 2,
      dstInset: destinationRadius + 2,
    );

    Path? dashPath;
    if (dashLength > 0) {
      final cached = _dashPaths[edge.semanticId];
      if (cached != null &&
          cached.a == trimmed.$1 &&
          cached.b == trimmed.$2 &&
          cached.dash == dashLength &&
          cached.gap == dashGap) {
        dashPath = cached.path;
      } else {
        dashPath = constellationEdgeDashPath(
          trimmed.$1,
          trimmed.$2,
          dash: dashLength,
          gap: dashGap,
        );
        _dashPaths[edge.semanticId] = (
          a: trimmed.$1,
          b: trimmed.$2,
          dash: dashLength,
          gap: dashGap,
          path: dashPath,
        );
      }
    }

    final paint = Paint()
      ..color = style.color.withValues(
        alpha: style.color.a * (edgeFadeBySemanticId[edge.semanticId] ?? 1),
      )
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    paintConstellationEdgeStroke(
      canvas,
      trimmed.$1,
      trimmed.$2,
      paint,
      dash: dashLength,
      gap: dashGap,
      endDots: style.endDots,
      dashPath: dashPath,
      twin: style.twin,
    );
    final pulse = forwardTreePulseReader?.call()[edge.semanticId];
    if (pulse != null && pulse > 0) {
      final t = pulse.clamp(0.0, 1.0);
      final centre = Offset.lerp(trimmed.$1, trimmed.$2, t)!;
      final r = strokeWidth * 4 * t + 2;
      final glow = Paint()
        ..color = scheme.primary.withValues(alpha: 0.35 * t)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(centre, r, glow);
    }
    if (edge.arrowAtDestination) {
      final tip = trimmed.$2;
      final base = trimmed.$1;
      final dir = tip - base;
      final len = dir.distance;
      if (len > 1e-6) {
        final u = dir / len;
        final v = Offset(-u.dy, u.dx);
        final ah = strokeWidth * 2.5;
        final aw = strokeWidth * 1.8;
        final path = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - u.dx * ah + v.dx * aw,
            tip.dy - u.dy * ah + v.dy * aw,
          )
          ..lineTo(
            tip.dx - u.dx * ah - v.dx * aw,
            tip.dy - u.dy * ah - v.dy * aw,
          )
          ..close();
        final fill = Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;
        canvas.drawPath(path, fill);
      }
    }
  }

  (Offset, Offset) _trim({
    required Offset src,
    required Offset dst,
    required double srcInset,
    required double dstInset,
  }) {
    final delta = dst - src;
    final length = delta.distance;
    if (length <= srcInset + dstInset) {
      return (src, dst);
    }
    final direction = delta / length;
    return (src + direction * srcInset, dst - direction * dstInset);
  }
}

void _syncComposerPersonPositions(
  ConstellationCubit cubit,
  ConstellationComposerCubit? composer,
) {
  if (composer == null ||
      composer.isClosed ||
      cubit.isClosed ||
      composer.createCubit == null) {
    return;
  }
  composer.updatePersonPositions({
    for (final entry
        in cubit.graphController.renderSnapshot.topology.nodesById.entries)
      if (entry.value.payload is FieldPersonNode)
        if (cubit.graphController.renderSnapshot.resolvePosition(entry.key)
            case final position?)
          (entry.value.payload as FieldPersonNode).id: Offset(
            position.x,
            position.y,
          ),
  });
}

/// The map marker that is the map's Tab stop (#615).
class _MapTabStop {
  _MapMarkerFocusNode? node;
}

/// Makes the map markers one Tab stop with roving focus (WAI-ARIA roving
/// tabindex, #615): of the markers, only the Tab stop is offered to Tab and
/// Shift+Tab; the others stay focusable, so the arrow keys and a screen
/// reader still reach them, and whichever marker gets focus becomes the
/// Tab stop; a press on a marker makes it the Tab stop without focusing it.
///
/// The Tab stop is the focused marker, else the marker focused or pressed
/// last while it is still on the map, else the first marker in reading
/// order: rows top to bottom (markers whose centres are within half a marker
/// height share a row), and within a row in the reading direction. The
/// widget (and paint) order of the graph view follows layout and drag
/// history, not the picture (#391). When the stop leaves the map (a filter,
/// a reload), the first marker in reading order takes over.
class _ConstellationMapReadingOrderPolicy extends FocusTraversalPolicy
    with DirectionalFocusTraversalPolicyMixin {
  /// The marker focused or pressed last; set by the marker itself.
  /// FocusTraversalPolicy is @immutable; the mutable stop lives in a box
  /// behind a final field (same pattern as the directional mixin's
  /// _policyData).
  final _tabStop = _MapTabStop();

  _MapMarkerFocusNode? get tabStop => _tabStop.node;

  set tabStop(_MapMarkerFocusNode? node) => _tabStop.node = node;

  /// Called as a marker goes away, so its node is not kept around.
  void forgetTabStop(FocusNode node) {
    if (identical(_tabStop.node, node)) _tabStop.node = null;
  }

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final members = descendants.toList();
    final FocusNode? known =
        currentNode is _MapMarkerFocusNode && members.contains(currentNode)
        ? currentNode
        : members.contains(_tabStop.node)
        ? _tabStop.node
        : null;
    // With the stop known, only it and the non-marker members are sorted;
    // without one, the full sort picks the first marker in reading order.
    final sorted = _readingOrder(
      known == null
          ? members
          : [
              for (final node in members)
                if (node is! _MapMarkerFocusNode || identical(node, known))
                  node,
            ],
      currentNode,
    );
    final stop = known ?? sorted.whereType<_MapMarkerFocusNode>().firstOrNull;
    return [
      for (final node in sorted)
        if (node is! _MapMarkerFocusNode || identical(node, stop)) node,
    ];
  }

  List<FocusNode> _readingOrder(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final context = currentNode.context;
    final rtl =
        context != null && Directionality.maybeOf(context) == TextDirection.rtl;
    final byTop = descendants.toList()
      ..sort((a, b) {
        final dy = a.rect.center.dy.compareTo(b.rect.center.dy);
        return dy != 0 ? dy : a.rect.center.dx.compareTo(b.rect.center.dx);
      });
    final sorted = <FocusNode>[];
    var start = 0;
    while (start < byTop.length) {
      final first = byTop[start].rect;
      var end = start + 1;
      while (end < byTop.length) {
        final next = byTop[end].rect;
        final band =
            (first.height < next.height ? first.height : next.height) / 2;
        if (next.center.dy - first.center.dy > band) {
          break;
        }
        end++;
      }
      final row = byTop.sublist(start, end)
        ..sort((a, b) {
          final dx = a.rect.center.dx.compareTo(b.rect.center.dx);
          return rtl ? -dx : dx;
        });
      sorted.addAll(row);
      start = end;
    }
    return sorted;
  }
}

/// One-time touch hold hint (#938), stored in field visibility (#645).
class _ConstellationFieldHoldHintBanner extends StatelessWidget {
  const _ConstellationFieldHoldHintBanner({required this.cubit});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      bloc: cubit,
      buildWhen: (previous, current) =>
          previous.visibility.fieldHoldHintDismissed !=
              current.visibility.fieldHoldHintDismissed ||
          previous.visibilityRestored != current.visibilityRestored ||
          previous.field != current.field ||
          previous.composition != current.composition,
      builder: (context, state) {
        if (!state.visibilityRestored ||
            state.visibility.fieldHoldHintDismissed ||
            state.viewMode != ConstellationViewMode.map) {
          return const SizedBox.shrink();
        }
        final field = state.field;
        if (field == null ||
            constellationFieldHasNoContacts(field, cubit.viewerId)) {
          return const SizedBox.shrink();
        }
        if (selection?.state.arranging ?? false) {
          return const SizedBox.shrink();
        }
        if (RendererBinding.instance.mouseTracker.mouseIsConnected) {
          return const SizedBox.shrink();
        }
        if (context.windowClass != WindowClass.compact) {
          return const SizedBox.shrink();
        }
        final l10n = L10n.of(context)!;
        final tt = context.tt;
        final theme = Theme.of(context);
        return Material(
          key: const Key('constellation.field_hold_hint'),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.screenHPadding,
              vertical: tt.tightGap,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.constellationFieldHoldHint,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: cubit.dismissFieldHoldHint,
                  child: Text(l10n.buttonOk),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

extension on ConstellationTagLens {
  /// People dim by themselves; Requests and Posts follow their author.
  bool isNodeDimmed(NodeDetails node) => switch (node) {
    FieldPersonNode() => isAuthorDimmed(node.id),
    FieldBeaconNode() => isAuthorDimmed(node.userId),
    _ => false,
  };
}
