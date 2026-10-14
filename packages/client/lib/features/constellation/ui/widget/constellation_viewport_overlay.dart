import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../bloc/constellation_cubit.dart';
import '../utils/constellation_presentation_frame.dart';
import '../utils/constellation_tap_resolver.dart';
import 'constellation_overflow_group.dart';
import 'constellation_request_status_marker.dart';

Size measureConstellationLabelPlate({
  required String text,
  required TextStyle style,
  required int maxLines,
  required double plateWidth,
  required EdgeInsets padding,
  required TextScaler textScaler,
  required TextDirection direction,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: '…',
    textDirection: direction,
    textScaler: textScaler,
  )..layout(maxWidth: plateWidth - padding.horizontal);
  return Size(
    painter.width + padding.horizontal,
    painter.height + padding.vertical,
  );
}

class ConstellationViewportOverlay extends StatefulWidget {
  const ConstellationViewportOverlay({
    required this.cubit,
    required this.frameHolder,
    super.key,
  });

  final ConstellationCubit cubit;
  final ConstellationPresentationFrameHolder frameHolder;

  @override
  State<ConstellationViewportOverlay> createState() =>
      _ConstellationViewportOverlayState();
}

class _ConstellationViewportOverlayState
    extends State<ConstellationViewportOverlay> {
  ConstellationDetailLevel _detail = ConstellationDetailLevel.normal;
  final Map<(String, int, double, double), Size> _labelMeasureCache = {};
  Locale? _cacheLocale;
  Brightness? _cacheBrightness;
  double? _cacheTextScaleKey;
  List<Object?>? _placementKey;
  ConstellationPresentationFrame? _placementFrame;
  Offset _placementOrigin = Offset.zero;
  // Label plates at `_placementOrigin`; a pan only translates this layer.
  Widget? _labelLayer;
  // Chip widgets built for the same placement; a pan only moves their rects.
  final _chipByAuthor = <String, Widget>{};
  // Scale and viewport size: the camera facts a translation leaves alone.
  late final ValueNotifier<(double, Size?)> _cameraShape;

  @override
  void initState() {
    super.initState();
    final controller = widget.cubit.graphController;
    _cameraShape = ValueNotifier(_shapeOf(controller));
    controller.cameraRevision.addListener(_onCamera);
  }

  @override
  void dispose() {
    widget.cubit.graphController.cameraRevision.removeListener(_onCamera);
    _cameraShape.dispose();
    super.dispose();
  }

  (double, Size?) _shapeOf(GraphController<NodeDetails, EdgeDetails> c) =>
      (c.cameraScale, c.viewportSize);

  void _onCamera() {
    _cameraShape.value = _shapeOf(widget.cubit.graphController);
  }

  void _maybeClearLabelCache(BuildContext context, int nodeCount) {
    final locale = Localizations.localeOf(context);
    final brightness = Theme.of(context).brightness;
    final textScaleKey = MediaQuery.textScalerOf(context).scale(13);
    if (_cacheLocale != locale ||
        _cacheBrightness != brightness ||
        _cacheTextScaleKey != textScaleKey ||
        _labelMeasureCache.length > 4 * nodeCount) {
      _labelMeasureCache.clear();
      _cacheLocale = locale;
      _cacheBrightness = brightness;
      _cacheTextScaleKey = textScaleKey;
    }
  }

  Size _measureLabel({
    required BuildContext context,
    required String text,
    required int maxLines,
    required double plateWidth,
    required EdgeInsets padding,
    required TextStyle style,
  }) {
    final textScaleKey = MediaQuery.textScalerOf(context).scale(13);
    final key = (text, maxLines, plateWidth, textScaleKey);
    return _labelMeasureCache.putIfAbsent(
      key,
      () => measureConstellationLabelPlate(
        text: text,
        style: style,
        maxLines: maxLines,
        plateWidth: plateWidth,
        padding: padding,
        textScaler: MediaQuery.textScalerOf(context),
        direction: Directionality.of(context),
      ),
    );
  }

  bool _nodeShowsBadge({
    required NodeDetails node,
    required ConstellationCubit cubit,
    required L10n l10n,
    required TenturaTokens tt,
  }) {
    return switch (node) {
      FieldPersonNode(:final person) => cubit.isAnchored(
        ConstellationAnchorTarget.person(person.id),
      ),
      FieldBeaconNode(request: final request?) =>
        cubit.isAnchored(ConstellationAnchorTarget.beacon(request.id)) ||
            constellationRequestStatusPresentation(
                  rawStatus: request.status,
                  l10n: l10n,
                  tt: tt,
                ) !=
                null,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      bloc: widget.cubit,
      buildWhen: (previous, current) =>
          previous.selectedPersonId != current.selectedPersonId ||
          previous.selectedRequestId != current.selectedRequestId ||
          previous.graphRevision != current.graphRevision ||
          previous.placementPhase != current.placementPhase ||
          previous.viewMode != current.viewMode,
      builder: (context, state) {
        if (state.viewMode != ConstellationViewMode.map) {
          return const SizedBox.shrink();
        }
        final controller = widget.cubit.graphController;
        return ListenableBuilder(
          listenable: Listenable.merge([controller, _cameraShape]),
          builder: (context, _) {
            if (!controller.canLayout) {
              widget.frameHolder.frame = null;
              return const SizedBox.shrink();
            }

            final viewport = controller.viewportSize;
            if (viewport == null || viewport.isEmpty) {
              return const SizedBox.shrink();
            }

            final snapshot = controller.renderSnapshot;
            final scale = controller.cameraScale;
            _detail = nextConstellationDetailLevel(scale, _detail);

            final configuredOrder = widget.cubit.orderedNodeIdsForPaint();
            final order = controller.orderedRenderNodeIds(
              snapshot,
              configuredPaintOrder: configuredOrder,
            );

            final nodeByGraphId = {
              for (final node in controller.nodes.whereType<NodeDetails>())
                tenturaGraphNodeId(node): node,
            };

            _maybeClearLabelCache(context, order.length);

            final tt = context.tt;
            final scheme = Theme.of(context).colorScheme;
            final l10n = L10n.of(context)!;
            final labelStyle = TenturaText.labelSmall(scheme.onSurface);
            final labelPadding = EdgeInsets.symmetric(
              horizontal: tt.iconTextGap,
              vertical: tt.tightGap,
            );
            final badgeOverhangScene = constellationMarkerBadgeOverhang(tt);
            final badgeOverhangViewport = badgeOverhangScene * scale;
            final gap = tt.tightGap;
            final viewerId = widget.cubit.viewerId;
            final selectedPersonId = state.selectedPersonId;
            final selectedRequestId = state.selectedRequestId;
            final rtl = Directionality.of(context) == TextDirection.rtl;

            final inputs = <ConstellationFrameNodeInput>[];
            final labelTexts = <String>[];
            for (final graphId in order) {
              final node = nodeByGraphId[graphId];
              if (node == null) {
                continue;
              }
              final scenePoint = snapshot.resolvePosition(graphId);
              if (scenePoint == null) {
                continue;
              }
              final centre = controller.sceneToViewportLocal(
                Offset(scenePoint.x, scenePoint.y),
              );
              final bodyDiameter = node.size * scale;

              final priority = switch (node) {
                FieldPersonNode(:final person)
                    when person.id == selectedPersonId =>
                  0,
                FieldBeaconNode(request: final request?)
                    when request.id == selectedRequestId =>
                  0,
                FieldPersonNode(:final person) when person.id == viewerId => 1,
                FieldPersonNode() => 2,
                FieldBeaconNode() => 3,
                _ => 3,
              };

              final ring = switch (node) {
                FieldPersonNode(:final ring) => ring,
                _ => 0,
              };

              final labelCandidate = constellationLabelCandidateForDetail(
                detail: _detail,
                priority: priority,
                ring: ring,
              );

              final (labelText, maxLines, plateWidth) = switch (node) {
                FieldPersonNode(:final person) => (
                  person.shownName,
                  1,
                  tt.graphLabelMaxWidthPerson,
                ),
                FieldBeaconNode(request: final request?) => (
                  request.title.isEmpty ? l10n.beaconViewTitle : request.title,
                  2,
                  tt.graphLabelMaxWidthRequest,
                ),
                _ => ('', 1, tt.graphLabelMaxWidthPerson),
              };

              final labelSize = labelText.isEmpty
                  ? Size.zero
                  : _measureLabel(
                      context: context,
                      text: labelText,
                      maxLines: maxLines,
                      plateWidth: plateWidth,
                      padding: labelPadding,
                      style: labelStyle,
                    );

              final badgeOverhang =
                  _nodeShowsBadge(
                    node: node,
                    cubit: widget.cubit,
                    l10n: l10n,
                    tt: tt,
                  )
                  ? badgeOverhangViewport
                  : 0.0;

              labelTexts.add(labelText);
              inputs.add(
                ConstellationFrameNodeInput(
                  id: graphId,
                  centre: centre,
                  bodyDiameter: bodyDiameter,
                  badgeOverhang: badgeOverhang,
                  labelSize: labelSize,
                  priority: priority,
                  ring: ring,
                  labelCandidate: labelCandidate,
                ),
              );
            }

            final chipAuthors = {
              ...widget.cubit.overflowHiddenCountByAuthor.keys,
              ...widget.cubit.expandedExtraCountByAuthor.keys,
            };
            final chipInputs = <ConstellationFrameChipInput>[];
            final chipContents = <(String?, int)>[];
            for (final authorId in chipAuthors) {
              GraphNodeId? authorGraphId;
              for (final graphId in order) {
                final candidate = nodeByGraphId[graphId];
                if (candidate is FieldPersonNode &&
                    candidate.person.id == authorId) {
                  authorGraphId = graphId;
                  break;
                }
              }
              if (authorGraphId == null) {
                continue;
              }
              final hidden =
                  widget.cubit.overflowHiddenCountByAuthor[authorId] ?? 0;
              final expanded = widget.cubit.isSatelliteOverflowExpanded(
                authorId,
              );
              final chipLabel = expanded
                  ? l10n.constellationFewerRequests
                  : l10n.constellationMoreRequests(hidden);
              final chipSize = constellationOverflowChipSize(
                context,
                chipLabel,
              );
              chipContents.add((
                widget.cubit.profileForPersonId(authorId)?.shownName,
                hidden,
              ));
              chipInputs.add(
                ConstellationFrameChipInput(
                  authorId: authorId,
                  authorGraphId: authorGraphId,
                  size: chipSize,
                ),
              );
            }

            // Exact scale buckets preserve marker geometry during zoom.
            // Translation is excluded; placement includes offscreen nodes
            // so a pan can reveal them without another collision pass.
            final placementKey = <Object?>[
              controller,
              controller.sceneRevision,
              scale,
              viewport,
              _detail,
              rtl,
              gap,
              Theme.of(context),
              _cacheLocale,
              _cacheTextScaleKey,
              for (final input in inputs)
                (
                  input.id,
                  input.bodyDiameter,
                  input.badgeOverhang,
                  input.labelSize,
                  input.priority,
                  input.ring,
                  input.labelCandidate,
                ),
              for (final chip in chipInputs)
                (chip.authorId, chip.authorGraphId, chip.size),
              ...labelTexts,
              ...chipContents,
            ];
            final origin = controller.sceneToViewportLocal(Offset.zero);
            if (_placementFrame == null ||
                !listEquals(_placementKey, placementKey)) {
              _placementKey = placementKey;
              _placementOrigin = origin;
              _labelLayer = null;
              _chipByAuthor.clear();
              _placementFrame = computeConstellationPresentationFrame(
                snapshot: snapshot,
                cameraRevision: controller.cameraRevision.value,
                detail: _detail,
                viewport: viewport,
                nodesInPaintOrder: inputs,
                chips: chipInputs,
                gap: gap,
                minTarget: kMinInteractiveDimension,
                rtl: rtl,
                cullToViewport: false,
              );
            }
            final placed = _placementFrame!;
            _labelLayer ??= () {
              final labelWidgets = <Widget>[];
              for (final graphId in placed.paintOrder) {
                final labelRect = placed.labels[graphId];
                if (labelRect == null) {
                  continue;
                }
                final node = nodeByGraphId[graphId];
                if (node == null) {
                  continue;
                }
                final (text, maxLines, plateWidth) = switch (node) {
                  FieldPersonNode(:final person) => (
                    person.shownName,
                    1,
                    tt.graphLabelMaxWidthPerson,
                  ),
                  FieldBeaconNode(request: final request?) => (
                    request.title.isEmpty
                        ? l10n.beaconViewTitle
                        : request.title,
                    2,
                    tt.graphLabelMaxWidthRequest,
                  ),
                  _ => ('', 1, tt.graphLabelMaxWidthPerson),
                };
                labelWidgets.add(
                  Positioned.fromRect(
                    rect: labelRect,
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: _LabelPlate(
                          key: ValueKey('constellation.label.$graphId'),
                          text: text,
                          maxLines: maxLines,
                          plateWidth: plateWidth,
                          style: labelStyle,
                          padding: labelPadding,
                        ),
                      ),
                    ),
                  ),
                );
              }
              return Stack(
                clipBehavior: Clip.none,
                children: labelWidgets,
              );
            }();

            // A pure pan only moves the cached layers; nothing above re-runs.
            return ValueListenableBuilder<int>(
              valueListenable: controller.cameraRevision,
              builder: (context, _, _) {
                final origin = controller.sceneToViewportLocal(Offset.zero);
                final frame = _placementFrame!.translated(
                  snapshot: snapshot,
                  cameraRevision: controller.cameraRevision.value,
                  delta: origin - _placementOrigin,
                );
                widget.frameHolder.frame = frame;

                final chipWidgets = <Widget>[];
                for (final entry in frame.chips.entries) {
                  final authorId = entry.key;
                  chipWidgets.add(
                    Positioned.fromRect(
                      rect: entry.value,
                      child: _chipByAuthor.putIfAbsent(authorId, () {
                        final person = widget.cubit.profileForPersonId(
                          authorId,
                        );
                        final authorName = person?.shownName ?? authorId;
                        final hidden =
                            widget
                                .cubit
                                .overflowHiddenCountByAuthor[authorId] ??
                            0;
                        return ConstellationOverflowGroup(
                          authorId: authorId,
                          authorName: authorName,
                          hiddenCount: hidden,
                        );
                      }),
                    ),
                  );
                }

                final postChipWidgets = <Widget>[];
                if (selectedRequestId != null) {
                  final count =
                      widget
                          .cubit
                          .postOverflowCountByPostId[selectedRequestId] ??
                      0;
                  final postGraphId = 'fr:$selectedRequestId';
                  final scenePoint =
                      count > 0 && nodeByGraphId.containsKey(postGraphId)
                      ? snapshot.resolvePosition(postGraphId)
                      : null;
                  if (scenePoint != null) {
                    final centre = controller.sceneToViewportLocal(
                      Offset(scenePoint.x, scenePoint.y),
                    );
                    final chipSize = constellationOverflowChipSize(
                      context,
                      '+$count',
                    );
                    final radius = nodeByGraphId[postGraphId]!.size * scale / 2;
                    postChipWidgets.add(
                      Positioned.fromRect(
                        rect: Rect.fromLTWH(
                          centre.dx + radius + gap,
                          centre.dy - chipSize.height / 2,
                          chipSize.width,
                          chipSize.height,
                        ),
                        child: ConstellationPostOverflowChip(
                          postId: selectedRequestId,
                          hiddenCount: count,
                        ),
                      ),
                    );
                  }
                }

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Transform.translate(
                      offset: origin - _placementOrigin,
                      child: RepaintBoundary(child: _labelLayer),
                    ),
                    ...chipWidgets,
                    ...postChipWidgets,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LabelPlate extends StatelessWidget {
  const _LabelPlate({
    required this.text,
    required this.maxLines,
    required this.plateWidth,
    required this.style,
    required this.padding,
    super.key,
  });

  final String text;
  final int maxLines;
  final double plateWidth;
  final TextStyle style;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(tt.buttonRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: padding,
        child: SizedBox(
          width: plateWidth - padding.horizontal,
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
