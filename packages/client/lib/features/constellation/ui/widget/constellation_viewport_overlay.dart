import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_state.dart';
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
      FieldPersonNode(:final person) =>
        cubit.isAnchored(ConstellationAnchorTarget.person(person.id)),
      FieldRequestNode(:final request) =>
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
          listenable: Listenable.merge([
            controller,
            controller.cameraRevision,
          ]),
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
                FieldPersonNode(:final person) when person.id == selectedPersonId =>
                  0,
                FieldRequestNode(:final request) when request.id == selectedRequestId =>
                  0,
                FieldPersonNode(:final person) when person.id == viewerId => 1,
                FieldPersonNode() => 2,
                FieldRequestNode() => 3,
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
                FieldRequestNode(:final request) => (
                    request.title.isEmpty
                        ? l10n.beaconViewTitle
                        : request.title,
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

              final badgeOverhang = _nodeShowsBadge(
                node: node,
                cubit: widget.cubit,
                l10n: l10n,
                tt: tt,
              )
                  ? badgeOverhangViewport
                  : 0.0;

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
              final expanded =
                  widget.cubit.isSatelliteOverflowExpanded(authorId);
              final chipLabel = expanded
                  ? l10n.constellationFewerRequests
                  : l10n.constellationMoreRequests(hidden);
              final chipSize = constellationOverflowChipSize(context, chipLabel);
              chipInputs.add(
                ConstellationFrameChipInput(
                  authorId: authorId,
                  authorGraphId: authorGraphId,
                  size: chipSize,
                ),
              );
            }

            final frame = computeConstellationPresentationFrame(
              snapshot: snapshot,
              cameraRevision: controller.cameraRevision.value,
              detail: _detail,
              viewport: viewport,
              nodesInPaintOrder: inputs,
              chips: chipInputs,
              gap: gap,
              minTarget: kMinInteractiveDimension,
              rtl: rtl,
            );
            widget.frameHolder.frame = frame;

            final labelWidgets = <Widget>[];
            for (final graphId in frame.paintOrder) {
              final labelRect = frame.labels[graphId];
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
                FieldRequestNode(:final request) => (
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

            final chipWidgets = <Widget>[];
            for (final entry in frame.chips.entries) {
              final authorId = entry.key;
              final rect = entry.value;
              final person = widget.cubit.profileForPersonId(authorId);
              final authorName = person?.shownName ?? authorId;
              final hidden =
                  widget.cubit.overflowHiddenCountByAuthor[authorId] ?? 0;
              chipWidgets.add(
                Positioned.fromRect(
                  rect: rect,
                  child: ConstellationOverflowGroup(
                    authorId: authorId,
                    authorName: authorName,
                    hiddenCount: hidden,
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                ...labelWidgets,
                ...chipWidgets,
              ],
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
