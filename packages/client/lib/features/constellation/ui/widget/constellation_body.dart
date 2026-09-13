import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/entity/constellation_anchor.dart';
import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_anchor_controls.dart';
import 'constellation_filter_bar.dart';
import 'constellation_request_status_marker.dart';
import 'constellation_overflow_group.dart';
import 'constellation_request_label.dart';
import 'constellation_request_preview_sheet.dart';
import 'constellation_text_view.dart';

class _CancelPlacementIntent extends Intent {
  const _CancelPlacementIntent();
}

class ConstellationBody extends StatefulWidget {
  const ConstellationBody({
    required this.legendExpanded,
    required this.onToggleLegend,
    super.key,
  });

  final bool legendExpanded;
  final VoidCallback onToggleLegend;

  static const _canvasSize = GraphCanvasSize.fixed(Size(4096, 4096));

  @override
  State<ConstellationBody> createState() => _ConstellationBodyState();
}

class _ConstellationBodyState extends State<ConstellationBody> {
  Size? _lastLabelBudgetViewport;
  double? _lastLabelBudgetTextScale;
  String? _selectionUnavailableMessage;

  void _syncLabelBudget(
    BuildContext context,
    ConstellationCubit cubit,
    Size viewport,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(14);
    if (_lastLabelBudgetViewport == viewport &&
        _lastLabelBudgetTextScale == scale) {
      return;
    }
    _lastLabelBudgetViewport = viewport;
    _lastLabelBudgetTextScale = scale;
    cubit.updateLabelBudgetContext(
      viewport: viewport,
      textScaleFactor: scale,
    );
  }

  void _onNodeTap(
    BuildContext context,
    ConstellationCubit cubit,
    NodeDetails node,
  ) {
    cubit.selectMapNode(node);
    if (node case FieldPersonNode(:final person) when person.id != cubit.viewerId) {
      context.read<GraphPersonContextCubit>().selectProfile(
        person,
        intentional: true,
      );
    }
  }

  Future<void> _showRequestPreview(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) async {
    final state = cubit.state;
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

    await showConstellationRequestPreviewSheet(
      context: context,
      request: request,
      authorDisplayName: authorDisplayName,
      connectionThroughName: connectionThroughName,
      onOpen: () => _openBeacon(context, request.id),
      onPrimaryAction: _primaryActionForRequest(context, cubit, request),
      onForward: constellationPreviewShowsForward(request)
          ? () => unawaited(_runForwardFlow(context, cubit, request))
          : null,
    );
    if (!context.mounted) {
      return;
    }
    cubit.selectRequest(null);
  }

  void _openBeacon(BuildContext context, String beaconId) {
    unawaited(context.router.push(BeaconViewRoute(id: beaconId)));
  }

  VoidCallback _primaryActionForRequest(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationRequest request,
  ) {
    return switch (request.heldState) {
      ConstellationHeldState.mine ||
      ConstellationHeldState.participant ||
      ConstellationHeldState.forwarded ||
      ConstellationHeldState.offered => () => _openBeacon(context, request.id),
      ConstellationHeldState.none => () {
        Navigator.of(context).pop();
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
    final reShow = await _runOfferFlow(context, cubit, request);
    if (reShow != null && context.mounted) {
      await _showRequestPreview(context, cubit, reShow);
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

  Widget _buildPersonContextOverlay(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state,
  ) {
    final personId = state.selectedPersonId;
    if (personId == null || personId == cubit.viewerId) {
      return const SizedBox.shrink();
    }

    final profile = cubit.profileForPersonId(personId);
    if (profile == null) {
      return const SizedBox.shrink();
    }

    final tt = context.tt;
    final panel = GraphPersonContextPanel(
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
    );

    if (context.windowClass == WindowClass.compact) {
      return Positioned(
        left: tt.screenHPadding,
        right: tt.screenHPadding,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: tt.rowGap),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.sizeOf(context).height *
                    tt.graphPersonContextCompactMaxHeightFraction,
              ),
              child: panel,
            ),
          ),
        ),
      );
    }

    return Positioned(
      top: tt.rowGap,
      right: tt.screenHPadding,
      bottom: tt.rowGap,
      width: tt.graphPersonContextWidth,
      child: SafeArea(
        left: false,
        child: panel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ConstellationCubit, ConstellationState>(
          listenWhen: (previous, current) =>
              previous.selectedRequestId != current.selectedRequestId,
          listener: (context, state) {
            final requestId = state.selectedRequestId;
            if (requestId == null) {
              return;
            }
            final cubit = context.read<ConstellationCubit>();
            final request = cubit.requestById(requestId);
            if (request == null) {
              final message = L10n.of(
                context,
              )!.constellationSelectionUnavailable;
              setState(() => _selectionUnavailableMessage = message);
              SemanticsService.announce(message, TextDirection.ltr);
              cubit.selectRequest(null);
              return;
            }
            setState(() => _selectionUnavailableMessage = null);
            unawaited(_showRequestPreview(context, cubit, request));
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
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
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

          final layoutAlgorithm = cubit.constellationSceneLayoutAlgorithm;

          final panelVisible = state.selectedPersonId != null;

          return Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape):
                  _CancelPlacementIntent(),
            },
            child: Actions(
              actions: {
                _CancelPlacementIntent: CallbackAction<_CancelPlacementIntent>(
                  onInvoke: (_) {
                    cubit.cancelPlacement();
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _syncLabelBudget(
                      context,
                      cubit,
                      Size(constraints.maxWidth, constraints.maxHeight),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ConstellationFieldNotices(),
                        const ConstellationEmptyFilterBanner(),
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
                    );
                  },
                ),
              ),
            ),
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
    return Stack(
      fit: StackFit.expand,
      children: [
        GraphView<NodeDetails, EdgeDetails<NodeDetails>>(
          controller: cubit.graphController,
          canvasSize: ConstellationBody._canvasSize,
          minScale: 0.1,
          maxScale: 3,
          layoutAlgorithm: layoutAlgorithm,
          layoutTransitionDuration: const Duration(milliseconds: 350),
          canDragNode: cubit.canDragNode,
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
          },
          onNodeDragEnd: (node, position) {
            final target = cubit.anchorTargetForNode(node);
            if (target == null) {
              return;
            }
            switch (cubit.state.placementPhase) {
              case ConstellationPlacementPhase.draggingExisting:
                unawaited(
                  cubit.onExistingNodeDrop(
                    target: target,
                    sceneCentre: position,
                  ),
                );
              case ConstellationPlacementPhase.draggingNew:
                unawaited(
                  cubit.onNewNodeDrop(
                    target: target,
                    sceneCentre: position,
                  ),
                );
              case ConstellationPlacementPhase.idle:
              case ConstellationPlacementPhase.provisionalNew:
                break;
            }
          },
          onNodeDragCancel: (_) => cubit.onPointerCancelDuringDrag(),
          onNodeTap: (node) => _onNodeTap(context, cubit, node),
          nodePaintOrder: cubit.orderedNodeIdsForPaint(),
          builder: (context, child) => _MapOverflowOverlay(
            cubit: cubit,
            child: child,
          ),
          edgePainter: ConstellationEdgePainter(
            edgeKinds: cubit.edgeKinds,
            colorScheme: Theme.of(context).colorScheme,
          ),
          labelBuilder: BottomLabelBuilder(
            labelSize: const Size(100, 20),
            builder: (_, node) => switch (node) {
              FieldPersonNode(:final person) => Text(
                person.shownName,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.labelSmall(
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
              FieldRequestNode(:final request) => Text(
                request.title,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.labelSmall(
                  Theme.of(context).colorScheme.onSurface,
                ),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
          nodeBuilder: (_, node) => switch (node) {
            FieldPersonNode(:final ring, :final person) =>
              _ConstellationMapNode(
                child: GraphNodeWidget(
                  key: TestIds.key(TestIds.graphNode(node.id)),
                  nodeDetails: node,
                  hiddenNeighborCount: null,
                  isOrigin: ring == 0,
                  isFocused: panelVisible && node.id == state.selectedPersonId,
                  onTap: () => _onNodeTap(context, cubit, node),
                ),
                markers: ConstellationRequestStatusMarker(
                  rawStatus: null,
                  isPinned: cubit.isAnchored(
                    ConstellationAnchorTarget.person(person.id),
                  ),
                  showStatus: false,
                ),
              ),
            FieldRequestNode(:final request) => _ConstellationMapNode(
              child: GraphNodeWidget(
                key: TestIds.key(TestIds.graphNode(node.id)),
                nodeDetails: node,
                hiddenNeighborCount: null,
                onTap: () => _onNodeTap(context, cubit, node),
              ),
              markers: ConstellationRequestStatusMarker(
                rawStatus: request.status,
                isPinned: cubit.isAnchored(
                  ConstellationAnchorTarget.beacon(request.id),
                ),
              ),
            ),
            _ => const SizedBox.shrink(),
          },
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
        if (widget.legendExpanded)
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
                padding: EdgeInsets.all(context.tt.rowGap),
                child: _buildLegendPanel(
                  context,
                  panelVisible: panelVisible,
                ),
              ),
            ),
          ),
        if (panelVisible) _buildPersonContextOverlay(context, cubit, state),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ConstellationProvisionalPlacementBar(
            controller: cubit.graphController,
          ),
        ),
      ],
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
    required this.markers,
  });

  final Widget child;
  final Widget markers;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          bottom: -tt.iconSize,
          child: markers,
        ),
      ],
    );
  }
}

class _MapOverflowOverlay extends StatelessWidget {
  const _MapOverflowOverlay({
    required this.cubit,
    required this.child,
  });

  final ConstellationCubit cubit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!cubit.graphController.canLayout) {
      return child;
    }

    final overlays = <Widget>[];

    for (final entry in cubit.overflowHiddenCountByAuthor.entries) {
      final authorId = entry.key;
      final hiddenCount = entry.value;
      if (hiddenCount <= 0) {
        continue;
      }

      FieldPersonNode? personNode;
      for (final node in cubit.graphController.nodes) {
        if (node is FieldPersonNode && node.id == authorId) {
          personNode = node;
          break;
        }
      }
      if (personNode == null) {
        continue;
      }

      final position = cubit.graphController.getPositionOrNull(personNode);
      if (position == null) {
        continue;
      }

      overlays.add(
        Positioned(
          left: position.dx - 80,
          top: position.dy + personNode.size / 2 + 48,
          child: ConstellationOverflowGroup(
            authorId: authorId,
            hiddenCount: hiddenCount,
          ),
        ),
      );
    }

    if (overlays.isEmpty) {
      return child;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        ...overlays,
      ],
    );
  }
}

class ConstellationEdgePainter
    implements EdgePainter<NodeDetails, EdgeDetails<NodeDetails>> {
  const ConstellationEdgePainter({
    required this.edgeKinds,
    required this.colorScheme,
  });

  final Map<GraphEdgeId, ConstellationEdgeKind> edgeKinds;
  final ColorScheme colorScheme;

  static const _pathStroke = 2.0;
  static const _attachmentStroke = 1.5;
  static const _stubStroke = 1.5;
  static const _dashLength = 6.0;
  static const _dashGap = 4.0;

  @override
  void paint(
    Canvas canvas,
    EdgeDetails<NodeDetails> edge,
    Offset src,
    Offset dst,
  ) {
    final pairSuffix =
        '${tenturaGraphNodeId(edge.source)}->${tenturaGraphNodeId(edge.destination)}';
    ConstellationEdgeKind? kind;
    for (final entry in edgeKinds.entries) {
      if (entry.key.endsWith(pairSuffix)) {
        kind = entry.value;
        break;
      }
    }
    if (kind == null) {
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    switch (kind) {
      case ConstellationEdgeKind.tier1Path:
        paint
          ..color = colorScheme.outline
          ..strokeWidth = _pathStroke;
        canvas.drawLine(src, dst, paint);
      case ConstellationEdgeKind.tier2Path:
        paint
          ..color = colorScheme.outlineVariant
          ..strokeWidth = _pathStroke;
        _drawDashedLine(canvas, src, dst, paint);
      case ConstellationEdgeKind.attachment:
        paint
          ..color = colorScheme.secondary
          ..strokeWidth = _attachmentStroke;
        final trimmed = _trimAttachmentLine(
          src: src,
          dst: dst,
          sourceRadius: edge.source.size / 2,
          destinationRadius: edge.destination.size / 2,
        );
        canvas.drawLine(trimmed.$1, trimmed.$2, paint);
      case ConstellationEdgeKind.ringStub:
        paint
          ..color = colorScheme.outlineVariant.withValues(alpha: 0.7)
          ..strokeWidth = _stubStroke;
        _drawDashedLine(canvas, src, dst, paint);
    }
  }

  (Offset, Offset) _trimAttachmentLine({
    required Offset src,
    required Offset dst,
    required double sourceRadius,
    required double destinationRadius,
  }) {
    final delta = dst - src;
    final length = delta.distance;
    if (length <= sourceRadius + destinationRadius) {
      return (src, dst);
    }
    final direction = delta / length;
    final start = src + direction * (sourceRadius + 2);
    final end = dst - direction * (destinationRadius + length * 0.15);
    return (start, end);
  }

  void _drawDashedLine(Canvas canvas, Offset src, Offset dst, Paint paint) {
    final delta = dst - src;
    final length = delta.distance;
    if (length <= 0) {
      return;
    }
    final direction = delta / length;
    var travelled = 0.0;
    while (travelled < length) {
      final dashEnd = math.min(travelled + _dashLength, length);
      canvas.drawLine(
        src + direction * travelled,
        src + direction * dashEnd,
        paint,
      );
      travelled += _dashLength + _dashGap;
    }
  }
}
