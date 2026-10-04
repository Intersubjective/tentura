import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/app/router/root_router.dart';
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
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../../domain/entity/constellation_field.dart';
import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';
import '../bloc/constellation_cubit.dart';
import '../utils/constellation_edge_style.dart';
import '../utils/constellation_presentation_frame.dart';
import '../utils/constellation_tap_resolver.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_camera_controls.dart';
import 'constellation_composer_radius.dart';
import 'constellation_composer_sheet.dart';
import 'constellation_create_entry.dart';
import 'constellation_filter_bar.dart';
import 'constellation_overflow_group.dart';
import 'constellation_request_status_marker.dart';
import 'constellation_node_semantics.dart';
import 'constellation_request_label.dart';
import 'constellation_request_preview_sheet.dart';
import 'constellation_post_preview_sheet.dart';
import 'constellation_text_view.dart';
import 'constellation_viewport_overlay.dart';

class _CancelPlacementIntent extends Intent {
  const _CancelPlacementIntent();
}

class ConstellationBody extends StatefulWidget {
  const ConstellationBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    this.presentationFrameHolder,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  /// When set (tests only), the viewport overlay writes its frame here.
  final ConstellationPresentationFrameHolder? presentationFrameHolder;

  static const _canvasSize = GraphCanvasSize.fixed(Size(4096, 4096));

  @override
  State<ConstellationBody> createState() => _ConstellationBodyState();
}

class _ConstellationBodyState extends State<ConstellationBody> {
  Size? _lastLabelBudgetViewport;
  double? _lastLabelBudgetTextScale;
  (Brightness, Locale, double)? _lastFootprintSyncKey;
  String? _selectionUnavailableMessage;
  final _internalFrameHolder = ConstellationPresentationFrameHolder();
  final _graphStackKey = GlobalKey();

  // Single owner of pin zoom detail: per-node history would diverge when a
  // node is recreated inside the hysteresis band.
  late final GraphController<NodeDetails, EdgeDetails> _graphController;
  late ConstellationDetailLevel _detail;

  @override
  void initState() {
    super.initState();
    _graphController = context.read<ConstellationCubit>().graphController;
    _detail = nextConstellationDetailLevel(
      _graphController.cameraScale,
      ConstellationDetailLevel.normal,
    );
    _graphController.cameraRevision.addListener(_onCamera);
  }

  @override
  void dispose() {
    _graphController.cameraRevision.removeListener(_onCamera);
    super.dispose();
  }

  // Only the pin badge is zoom-gated; rebuild solely on detail-level change.
  void _onCamera() {
    final next = nextConstellationDetailLevel(
      _graphController.cameraScale,
      _detail,
    );
    if (next != _detail) {
      setState(() => _detail = next);
    }
  }

  ConstellationPresentationFrameHolder get _frameHolder =>
      widget.presentationFrameHolder ?? _internalFrameHolder;

  void _scheduleLabelBudgetSync(BuildContext context, Size viewport) {
    final style = TenturaText.labelSmall(
      Theme.of(context).colorScheme.onSurface,
    );
    final reference = style.fontSize!;
    final ratio = MediaQuery.textScalerOf(context).scale(reference) / reference;
    final footprintKey = (
      Theme.of(context).brightness,
      Localizations.localeOf(context),
      ratio,
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
    final cubit = context.read<ConstellationCubit>();
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
        _syncFootprintMetrics(context);
      }
    });
  }

  void _syncFootprintMetrics(BuildContext context) {
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
      text: 'Ág\nÁg',
      style: style,
      maxLines: 2,
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
    cubit.selectMapNode(node);
    if (cubit.state.isComposing) {
      return;
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

  Future<void> _dismissRequestPreview(ConstellationCubit cubit) async {
    cubit.selectRequest(null);
  }

  void _openBeacon(
    BuildContext context,
    String beaconId, {
    String? viewTab,
  }) {
    unawaited(() async {
      await context.router.push(
        BeaconViewRoute(id: beaconId, viewTab: viewTab),
      );
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
        await context.router.push(ForwardBeaconRoute(beaconId: request.id));
    }
  }

  Future<void> _runOfferFlowAndMaybeReopenPreview(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) async {
    final requestId = request.id;
    await _dismissRequestPreview(cubit);
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
          allowEmptyMessage: false,
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
            return await _runOfferFlow(
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
            return await _runOfferFlow(
              context,
              cubit,
              request,
              preservedMessage: outcome.message,
              preservedHelpTypes: outcome.helpTypesWire,
            );
        }
    }
  }

  void _showActionMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildContextOverlay(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state,
  ) {
    final personId = state.selectedPersonId;
    if (personId != null && personId != cubit.viewerId) {
      final profile = cubit.profileForPersonId(personId);
      if (profile == null) {
        return const SizedBox.shrink();
      }
      return AdaptiveContextOverlay(
        child: GraphPersonContextPanel(
          profile: profile,
          focusedNode: UserNode(user: profile),
          discoverableRequests: cubit.discoverableRequestsForPerson(personId),
          requestsExpanded: state.expandedPersonIds.contains(personId),
          onToggleRequestsExpanded: () =>
              cubit.togglePersonRequestsExpanded(personId),
          onDiscoverableRequestTap: (request) {
            cubit.selectPerson(null);
            cubit.selectRequest(request.id);
          },
          footer: ConstellationAnchorTargetButton(
            target: ConstellationAnchorTarget.person(personId),
          ),
        ),
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
        return AdaptiveContextOverlay(
          child: ConstellationPostPreviewSheet(
            post: post,
            authorDisplayName:
                cubit.profileForPersonId(post.authorId)?.shownName ?? '',
            onOpen: () => _openBeacon(context, post.id),
            onClose: () => cubit.selectRequest(null),
          ),
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

    return AdaptiveContextOverlay(
      child: ConstellationRequestPreviewSheet(
        request: request,
        authorDisplayName: authorDisplayName,
        connectionThroughName: connectionThroughName,
        onOpen: () => _openBeacon(context, request.id),
        onPrimaryAction: _primaryActionForRequest(context, cubit, request),
        onForward: constellationPreviewShowsForward(request)
            ? () => unawaited(_runForwardFlow(context, cubit, request))
            : null,
        onClose: () => unawaited(_dismissRequestPreview(cubit)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
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
            SemanticsService.announce(message, TextDirection.ltr);
            cubit.selectRequest(null);
          },
        ),
        BlocListener<GraphPersonContextCubit, GraphPersonContextState>(
          listenWhen: (previous, current) =>
              previous.dismissedFocusId != current.dismissedFocusId &&
              current.dismissedFocusId != null,
          listener: (context, state) {
            context.read<ConstellationCubit>().selectPerson(null);
          },
        ),
      ],
      child: BlocBuilder<ConstellationCubit, ConstellationState>(
        buildWhen: (previous, current) =>
            previous.status != current.status ||
            previous.graphRevision != current.graphRevision ||
            previous.loadError != current.loadError ||
            previous.selectedPersonId != current.selectedPersonId ||
            previous.selectedRequestId != current.selectedRequestId ||
            previous.expandedPersonIds != current.expandedPersonIds ||
            previous.viewMode != current.viewMode ||
            previous.loadedAt != current.loadedAt ||
            previous.filterCapabilitySlugs != current.filterCapabilitySlugs ||
            previous.filterLocation != current.filterLocation ||
            previous.filterTiming != current.filterTiming ||
            previous.filterIncludeUnspecified !=
                current.filterIncludeUnspecified ||
            previous.placementPhase != current.placementPhase ||
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
              final theme = Theme.of(context);

              if (state.status is StateIsLoading && state.field == null) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(child: CircularProgressIndicator()),
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

              final layoutAlgorithm = cubit.graphSceneLayoutAlgorithm;

              final panelVisible =
                  state.selectedPersonId != null ||
                  state.selectedRequestId != null;

              return Shortcuts(
                shortcuts: const {
                  SingleActivator(LogicalKeyboardKey.escape):
                      _CancelPlacementIntent(),
                },
                child: Actions(
                  actions: {
                    _CancelPlacementIntent:
                        CallbackAction<_CancelPlacementIntent>(
                          onInvoke: (_) {
                            final composer = maybeConstellationComposer(
                              context,
                            );
                            if (cubit.state.isComposing && composer != null) {
                              unawaited(() async {
                                await composer.cancel();
                                await composer.finish();
                              }());
                            } else {
                              cubit.cancelPlacement();
                            }
                            return null;
                          },
                        ),
                  },
                  child: Focus(
                    autofocus: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!state.isComposing) ...[
                          const ConstellationFieldNotices(),
                          const ConstellationEmptyFilterBanner(),
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
                                key: const Key(
                                  'constellation.selection_unavailable',
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: IndexedStack(
                            index: state.viewMode == ConstellationViewMode.map
                                ? 0
                                : 1,
                            sizing: StackFit.expand,
                            children: [
                              _buildGraphStack(
                                context,
                                cubit,
                                state,
                                layoutAlgorithm,
                                panelVisible,
                              ),
                              const ConstellationTextView(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGraphStack(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state,
    SceneLayoutAlgorithm layoutAlgorithm,
    bool panelVisible,
  ) {
    final cameraInsets = ConstellationCameraControls.cameraViewportInsets(
      context,
      contextPanelVisible: panelVisible,
    );
    final tt = context.tt;
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

    return Stack(
      key: _graphStackKey,
      fit: StackFit.expand,
      children: [
        GraphView<NodeDetails, EdgeDetails>(
          controller: cubit.graphController,
          canvasSize: ConstellationBody._canvasSize,
          canvasBackgroundBuilder: composer == null
              ? null
              : (_) => ConstellationComposerCircle(composer: composer),
          onCanvasSecondaryTap: composer == null || composer.createCubit != null
              ? null
              : offerCreate,
          onCanvasLongPress: composer == null || composer.createCubit != null
              ? null
              : offerCreate,
          minScale: 0.1,
          maxScale: 3,
          layoutAlgorithm: layoutAlgorithm,
          layoutTransitionDuration: const Duration(milliseconds: 350),
          canDragNode: cubit.canDragNode,
          transformNodeDragPosition: cubit.clampClusterDragPosition,
          onNodeDragStart: (node, position) {
            final target = cubit.anchorTargetForNode(node);
            if (target == null) {
              return;
            }
            if (cubit.isAnchored(target)) {
              cubit.beginDragExisting(target: target);
            } else {
              cubit.beginDragNew(target: target);
            }
          },
          onNodeDragUpdate: (node, position) {
            cubit.updateDragPresentation(
              nodeId: node.id,
              sceneCentre: position,
            );
            _syncComposerPersonPositions(cubit, composer);
          },
          onNodeDragEnd: (node, position) {
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
                        (_) => _syncComposerPersonPositions(cubit, composer),
                      ),
                );
              case ConstellationPlacementPhase.idle:
              case ConstellationPlacementPhase.composing:
                break;
            }
          },
          onNodeDragCancel: (_) {
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
                !identical(frame.snapshot, controller.renderSnapshot) ||
                frame.cameraRevision != controller.cameraRevision.value) {
              return null;
            }
            return resolveConstellationTap(
              frame,
              controller.sceneToViewportLocal(scenePosition),
            );
          },
          edgePainter: ConstellationEdgePainter(
            edgeKindByPair: cubit.edgeKindByPair,
            edgeFadeBySemanticId: cubit.edgeFadeBySemanticId,
            tt: context.tt,
            scheme: Theme.of(context).colorScheme,
            repaint: cubit.graphController.cameraRevision,
            cameraScale: () => cubit.graphController.cameraScale,
          ),
          labelBuilder: null,
          nodeBuilder: (_, node) {
            final l10n = L10n.of(context)!;
            final tt = context.tt;
            final scheme = Theme.of(context).colorScheme;
            final mapNode = switch (node) {
              FieldPersonNode(:final ring, :final person) =>
                _ConstellationMapNode(
                  detail: _detail,
                  child: GraphNodeWidget(
                    key: TestIds.key(TestIds.graphNode(node.id)),
                    nodeDetails: node,
                    hiddenNeighborCount: null,
                    isOrigin: ring == 0,
                    isFocused:
                        panelVisible && node.id == state.selectedPersonId,
                    onTap: null,
                  ),
                  pinBadge:
                      cubit.isAnchored(
                        ConstellationAnchorTarget.person(person.id),
                      )
                      ? ExcludeSemantics(
                          child: ConstellationMarkerBadge.pin(
                            l10n: l10n,
                            tt: tt,
                            scheme: scheme,
                          ),
                        )
                      : null,
                  statusBadge: null,
                ),
              FieldBeaconNode(request: final request?) => _ConstellationMapNode(
                detail: _detail,
                child: GraphNodeWidget(
                  key: TestIds.key(TestIds.graphNode(node.id)),
                  nodeDetails: node,
                  hiddenNeighborCount: null,
                  isFocused: state.selectedRequestId == request.id,
                  onTap: null,
                ),
                pinBadge:
                    cubit.isAnchored(
                      ConstellationAnchorTarget.beacon(request.id),
                    )
                    ? ExcludeSemantics(
                        child: ConstellationMarkerBadge.pin(
                          l10n: l10n,
                          tt: tt,
                          scheme: scheme,
                        ),
                      )
                    : null,
                statusBadge:
                    constellationRequestStatusPresentation(
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
              ),
              FieldBeaconNode(post: final post?) => _ConstellationMapNode(
                detail: _detail,
                child: GraphNodeWidget(
                  key: TestIds.key(TestIds.graphNode(node.id)),
                  nodeDetails: node,
                  hiddenNeighborCount: null,
                  isFocused: state.selectedRequestId == post.id,
                  onTap: null,
                ),
                pinBadge:
                    cubit.isAnchored(ConstellationAnchorTarget.beacon(post.id))
                    ? ExcludeSemantics(
                        child: ConstellationMarkerBadge.pin(
                          l10n: l10n,
                          tt: tt,
                          scheme: scheme,
                        ),
                      )
                    : null,
                // Posts carry no lifecycle status (FieldBeaconNode.hasStatusMarker).
                statusBadge: null,
              ),
              _ => const SizedBox.shrink(),
            };
            if (mapNode is! _ConstellationMapNode) {
              return mapNode;
            }
            return _wrapConstellationMapNodeSemantics(
              context: context,
              cubit: cubit,
              state: state,
              node: node,
              panelVisible: panelVisible,
              mapNode: mapNode,
            );
          },
        ),
        Positioned.fill(
          child: ConstellationViewportOverlay(
            cubit: cubit,
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
                      onOpenFullForm: (route) => unawaited(() async {
                        await context.router.push(route);
                        if (context.mounted) await cubit.load();
                      }()),
                    ),
                  ),
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
              child: ConstellationCameraControls(
                cubit: cubit,
                viewportInsets: cameraInsets,
              ),
            ),
          ),
        ),
        if (widget.legendExpanded && !state.isComposing)
          Positioned(
            left: 0,
            bottom: panelVisible && context.windowClass == WindowClass.compact
                ? null
                : 0,
            top: panelVisible && context.windowClass == WindowClass.compact
                ? 0
                : null,
            child: SafeArea(
              top: panelVisible && context.windowClass == WindowClass.compact,
              bottom:
                  !(panelVisible && context.windowClass == WindowClass.compact),
              right: false,
              child: Padding(
                padding: EdgeInsets.all(tt.rowGap),
                child: _buildLegendPanel(
                  context,
                  panelVisible: panelVisible,
                ),
              ),
            ),
          ),
        if (panelVisible) _buildContextOverlay(context, cubit, state),
      ],
    );
  }

  Widget _wrapConstellationMapNodeSemantics({
    required BuildContext context,
    required ConstellationCubit cubit,
    required ConstellationState state,
    required NodeDetails node,
    required bool panelVisible,
    required _ConstellationMapNode mapNode,
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
    return Semantics(
      button: !isEgo,
      selected: selected,
      label: constellationNodeSemanticLabel(
        l10n: l10n,
        tt: tt,
        cubit: cubit,
        node: node,
      ),
      onTap: isEgo ? null : () => _onNodeTap(context, cubit, node),
      child: MouseRegion(
        cursor: isEgo ? MouseCursor.defer : SystemMouseCursors.click,
        child: ExcludeSemantics(child: mapNode),
      ),
    );
  }

  Widget _buildLegendPanel(
    BuildContext context, {
    required bool panelVisible,
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
    final media = MediaQuery.of(context);
    final maxHeight =
        media.size.height *
            (1 - tt.graphPersonContextCompactMaxHeightFraction) -
        media.padding.top -
        media.padding.bottom -
        tt.rowGap * 4;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: legend),
    );
  }
}

class _ConstellationMapNode extends StatelessWidget {
  const _ConstellationMapNode({
    required this.child,
    required this.detail,
    this.pinBadge,
    this.statusBadge,
  });

  final Widget child;
  final ConstellationDetailLevel detail;
  final Widget? pinBadge;
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final overhang = constellationMarkerBadgeOverhang(tt);
    final pinBadge = this.pinBadge;
    final statusBadge = this.statusBadge;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        if (statusBadge != null)
          PositionedDirectional(
            top: -overhang,
            start: -overhang,
            child: statusBadge,
          ),
        if (pinBadge != null && detail == ConstellationDetailLevel.normal)
          PositionedDirectional(
            top: -overhang,
            end: -overhang,
            child: pinBadge,
          ),
      ],
    );
  }
}

class ConstellationEdgePainter
    implements RepaintingEdgePainter<NodeDetails, EdgeDetails> {
  const ConstellationEdgePainter({
    required this.edgeKindByPair,
    this.edgeFadeBySemanticId = const {},
    required this.tt,
    required this.scheme,
    required this.repaint,
    required this.cameraScale,
  });

  final Map<String, ConstellationEdgeKind> edgeKindByPair;
  final Map<String, double> edgeFadeBySemanticId;
  final TenturaTokens tt;
  final ColorScheme scheme;
  @override
  final Listenable repaint;
  final double Function() cameraScale;

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
    );
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
      composer.createCubit == null)
    return;
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
