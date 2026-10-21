import 'package:flutter/foundation.dart' show listEquals, mapEquals;
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
  // Bumped by every scene change except a pure drag move of the same nodes.
  final _structure = ValueNotifier<int>(0);
  // Drives the cheap per-move layer: camera pans and drag moves.
  final _frameTick = ValueNotifier<int>(0);
  late GraphSceneSnapshot<NodeDetails, EdgeDetails> _seenSnapshot;
  // Dragged nodes at placement time: their scene point and cached plate.
  final _placementScene = <GraphNodeId, Offset>{};
  // Nodes a layout transition moves, at placement time; their cached plates
  // shift in place so the layer is not rebuilt per frame.
  final _transitionScene = <GraphNodeId, Offset>{};
  // Bumped by transition frames only: shifts the plates of _transitionScene.
  final _transitionTick = ValueNotifier<int>(0);
  // Plate widgets by node: an identical widget instance is not rebuilt when
  // the label layer is re-placed, so a layout transition keeps them as built.
  final _plateCache =
      <GraphNodeId, ((String, int, double, TextStyle, EdgeInsets), Widget)>{};
  final _draggedPlates = <GraphNodeId, Widget>{};
  final _chipAuthorGraphId = <String, GraphNodeId>{};

  @override
  void initState() {
    super.initState();
    final controller = widget.cubit.graphController;
    _cameraShape = ValueNotifier(_shapeOf(controller));
    _seenSnapshot = controller.renderSnapshot;
    controller.cameraRevision.addListener(_onCamera);
    controller.addListener(_onController);
  }

  @override
  void dispose() {
    final controller = widget.cubit.graphController;
    controller.cameraRevision.removeListener(_onCamera);
    controller.removeListener(_onController);
    _cameraShape.dispose();
    _structure.dispose();
    _frameTick.dispose();
    _transitionTick.dispose();
    super.dispose();
  }

  (double, Size?) _shapeOf(GraphController<NodeDetails, EdgeDetails> c) =>
      (c.cameraScale, c.viewportSize);

  void _onCamera() {
    _cameraShape.value = _shapeOf(widget.cubit.graphController);
    _frameTick.value++;
  }

  void _onController() {
    final next = widget.cubit.graphController.renderSnapshot;
    final previous = _seenSnapshot;
    _seenSnapshot = next;
    if (_isTransitionMoveOnly(previous, next)) {
      _transitionTick.value++;
      _frameTick.value++;
    } else if (_isDragMoveOnly(previous, next)) {
      _frameTick.value++;
    } else {
      _structure.value++;
    }
  }

  // A layout-transition frame, the one that ends it, or a repeat notification:
  // topology, layout and presentation are unchanged, so only interpolated
  // positions may differ and cached labels and chips are translated like a
  // drag move.
  static bool _isTransitionMoveOnly(
    GraphSceneSnapshot<NodeDetails, EdgeDetails> a,
    GraphSceneSnapshot<NodeDetails, EdgeDetails> b,
  ) {
    if (!identical(a.topology, b.topology) ||
        !identical(a.layout, b.layout) ||
        !mapEquals(a.seedPositions, b.seedPositions)) {
      return false;
    }
    final pa = a.presentation;
    final pb = b.presentation;
    return mapEquals(pa.overrides, pb.overrides) &&
        listEquals(pa.paintOrder, pb.paintOrder) &&
        mapEquals(pa.holds, pb.holds);
  }

  static bool _isDragMoveOnly(
    GraphSceneSnapshot<NodeDetails, EdgeDetails> a,
    GraphSceneSnapshot<NodeDetails, EdgeDetails> b,
  ) {
    if (!identical(a.topology, b.topology) ||
        !identical(a.layout, b.layout) ||
        !identical(a.transition, b.transition) ||
        !mapEquals(a.seedPositions, b.seedPositions)) {
      return false;
    }
    final pa = a.presentation;
    final pb = b.presentation;
    if (pa.overrides.length != pb.overrides.length ||
        !listEquals(pa.paintOrder, pb.paintOrder) ||
        !mapEquals(pa.holds, pb.holds)) {
      return false;
    }
    var moved = false;
    for (final entry in pb.overrides.entries) {
      final old = pa.overrides[entry.key];
      if (old == null) {
        return false;
      }
      if (old != entry.value) {
        moved = true;
      }
    }
    return moved;
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
          previous.viewMode != current.viewMode,
      builder: (context, state) {
        if (state.viewMode != ConstellationViewMode.map) {
          return const SizedBox.shrink();
        }
        final controller = widget.cubit.graphController;
        return ListenableBuilder(
          listenable: Listenable.merge([_structure, _cameraShape]),
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
              ...(snapshot.presentation.overrides.keys.toList()..sort()),
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
              _draggedPlates.clear();
              _placementScene.clear();
              _chipAuthorGraphId.clear();
              for (final id in snapshot.presentation.overrides.keys) {
                final point = snapshot.resolvePosition(id);
                if (point != null) {
                  _placementScene[id] = Offset(point.x, point.y);
                }
              }
              _transitionScene.clear();
              for (final id
                  in snapshot.transition?.positions.keys ??
                      const <GraphNodeId>[]) {
                final point = snapshot.resolvePosition(id);
                if (point != null && !_placementScene.containsKey(id)) {
                  _transitionScene[id] = Offset(point.x, point.y);
                }
              }
              for (final chip in chipInputs) {
                _chipAuthorGraphId[chip.authorId] = chip.authorGraphId;
              }
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
                final plateKey = (
                  text,
                  maxLines,
                  plateWidth,
                  labelStyle,
                  labelPadding,
                );
                final cached = _plateCache[graphId];
                final plate = cached != null && cached.$1 == plateKey
                    ? cached.$2
                    : IgnorePointer(
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
                      );
                _plateCache[graphId] = (plateKey, plate);
                // A dragged node's plate follows it outside the cached layer.
                if (_placementScene.containsKey(graphId)) {
                  _draggedPlates[graphId] = plate;
                  continue;
                }
                final start = _transitionScene[graphId];
                labelWidgets.add(
                  Positioned.fromRect(
                    key: ValueKey('constellation.slot.$graphId'),
                    rect: labelRect,
                    child: ValueListenableBuilder<int>(
                      valueListenable: _transitionTick,
                      child: plate,
                      builder: (_, _, child) {
                        final now = start == null
                            ? null
                            : controller.getPositionOrNullForId(graphId);
                        return Transform.translate(
                          offset: now == null
                              ? Offset.zero
                              : (now - start!) * scale,
                          child: child,
                        );
                      },
                    ),
                  ),
                );
              }
              _plateCache.removeWhere(
                (id, _) => !placed.labels.containsKey(id),
              );
              return Stack(
                clipBehavior: Clip.none,
                children: labelWidgets,
              );
            }();

            // A pure pan only moves the cached layers; nothing above re-runs.
            return ValueListenableBuilder<int>(
              valueListenable: _frameTick,
              builder: (context, _, _) {
                final origin = controller.sceneToViewportLocal(Offset.zero);
                final nodeDeltas = <GraphNodeId, Offset>{};
                for (final entry in [
                  ..._placementScene.entries,
                  ..._transitionScene.entries,
                ]) {
                  final now = controller.getPositionOrNullForId(entry.key);
                  if (now != null) {
                    nodeDeltas[entry.key] = (now - entry.value) * scale;
                  }
                }
                final chipDeltas = <String, Offset>{};
                for (final entry in _chipAuthorGraphId.entries) {
                  final delta = nodeDeltas[entry.value];
                  if (delta != null) {
                    chipDeltas[entry.key] = delta;
                  }
                }
                final frame = _placementFrame!
                    .translated(
                      snapshot: controller.renderSnapshot,
                      cameraRevision: controller.cameraRevision.value,
                      delta: origin - _placementOrigin,
                    )
                    .withDragShifts(
                      nodeDeltas: nodeDeltas,
                      chipDeltas: chipDeltas,
                    );
                widget.frameHolder.frame = frame;

                final chipWidgets = <Widget>[];
                for (final entry in frame.chips.entries) {
                  final authorId = entry.key;
                  chipWidgets.add(
                    Positioned.fromRect(
                      key: ValueKey('constellation.chip.$authorId'),
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

                final draggedLabels = <Widget>[
                  for (final entry in _draggedPlates.entries)
                    if (frame.labels[entry.key] case final rect?)
                      Positioned.fromRect(
                        key: ValueKey('constellation.dragged.${entry.key}'),
                        rect: rect,
                        child: entry.value,
                      ),
                ];

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
                      ? controller.getPositionOrNullForId(postGraphId)
                      : null;
                  if (scenePoint != null) {
                    final centre = controller.sceneToViewportLocal(scenePoint);
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
                    ...draggedLabels,
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
