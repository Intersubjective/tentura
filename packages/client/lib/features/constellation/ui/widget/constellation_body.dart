import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/features/beacon_view/ui/util/help_offer_types_wire.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/bloc/graph_person_context_cubit.dart';
import 'package:tentura/features/graph/ui/utils/tentura_layout_algorithms.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_mode.dart';
import 'package:tentura/features/graph/ui/widget/graph_legend_panel.dart';
import 'package:tentura/features/graph/ui/widget/graph_node_widget.dart';
import 'package:tentura/features/graph/ui/widget/graph_person_context_panel.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../../domain/entity/constellation_field.dart';
import '../bloc/constellation_cubit.dart';
import 'constellation_request_label.dart';
import 'constellation_request_preview_sheet.dart';
import 'constellation_snapshot_bar.dart';

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
  void _onNodeTap(BuildContext context, ConstellationCubit cubit, NodeDetails node) {
    switch (node) {
      case FieldPersonNode(:final person):
        if (person.id == cubit.viewerId) {
          return;
        }
        cubit.selectPerson(person.id);
        context.read<GraphPersonContextCubit>().selectProfile(
          person,
          intentional: true,
        );
      case FieldRequestNode(:final request):
        cubit.selectRequest(request.id);
      default:
        break;
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
        unawaited(_runOfferFlowAndMaybeReopenPreview(
          context,
          cubit,
          request,
        ));
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
        :final beacon,
        :final request,
        :final viewerHasActiveHelpOffer,
      ):
        if (cubit.coverageRequiresExplicitBackupChoice(
          snapshotRequest: snapshotRequest,
          freshBeacon: beacon,
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
          automaticSlugs: beacon.needs,
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
              cubit.selectRequest(null);
              return;
            }
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
            previous.expandedPersonIds != current.expandedPersonIds,
        builder: (context, state) {
          final cubit = context.read<ConstellationCubit>();
          final tt = context.tt;

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

          final layoutAlgorithm = ConstellationLayoutAlgorithm(
            egoId: cubit.layoutEgoId,
            paths: resolved.paths,
            keptPeerIds: resolved.keptPeerIds,
            maxHops: kConstellationLayoutMaxHops,
            visibleRequestsByAuthor: cubit.layoutVisibleRequestsByAuthor,
            egoOwnRequestIds: cubit.layoutEgoOwnRequestIds,
          );

          final panelVisible = state.selectedPersonId != null;

          return Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConstellationSnapshotBar(),
                  Expanded(
                    child: _buildGraphStack(
                      context,
                      cubit,
                      state,
                      layoutAlgorithm,
                      panelVisible,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGraphStack(
    BuildContext context,
    ConstellationCubit cubit,
    ConstellationState state,
    ConstellationLayoutAlgorithm layoutAlgorithm,
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
                  FieldPersonNode(:final ring) => GraphNodeWidget(
                    key: TestIds.key(TestIds.graphNode(node.id)),
                    nodeDetails: node,
                    hiddenNeighborCount: null,
                    isOrigin: ring == 0,
                    isFocused:
                        panelVisible && node.id == state.selectedPersonId,
                    onTap: () => _onNodeTap(context, cubit, node),
                  ),
                  FieldRequestNode() => GraphNodeWidget(
                    key: TestIds.key(TestIds.graphNode(node.id)),
                    nodeDetails: node,
                    hiddenNeighborCount: null,
                    onTap: () => _onNodeTap(context, cubit, node),
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
              if (panelVisible)
                _buildPersonContextOverlay(context, cubit, state),
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

class ConstellationEdgePainter
    implements EdgePainter<NodeDetails, EdgeDetails<NodeDetails>> {
  const ConstellationEdgePainter({
    required this.edgeKinds,
    required this.colorScheme,
  });

  final Map<String, ConstellationEdgeKind> edgeKinds;
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
    final kind = edgeKinds['${edge.source.id}\0${edge.destination.id}'];
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
