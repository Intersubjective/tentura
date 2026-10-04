import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';

import '../../domain/radius_recipient_selection.dart';
import '../bloc/constellation_composer_cubit.dart';

/// Scene-space radius circle of the composer; paints nothing before start.
class ConstellationComposerCircle extends StatelessWidget {
  const ConstellationComposerCircle({required this.composer, super.key});

  final ConstellationComposerCubit composer;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final strokeWidth = context.tt.tightGap / 2;
    return BlocBuilder<ConstellationComposerCubit, RadiusRecipientSelection>(
      bloc: composer,
      builder: (_, selection) => composer.createCubit == null
          ? const SizedBox.shrink()
          : IgnorePointer(
              child: CustomPaint(
                painter: _CirclePainter(
                  selection: selection,
                  color: color,
                  strokeWidth: strokeWidth,
                ),
              ),
            ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  const _CirclePainter({
    required this.selection,
    required this.color,
    required this.strokeWidth,
  });

  final RadiusRecipientSelection selection;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawCircle(
        selection.center,
        selection.radius,
        Paint()..color = color.withValues(alpha: 0.08),
      )
      ..drawCircle(
        selection.center,
        selection.radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
  }

  @override
  bool shouldRepaint(_CirclePainter old) =>
      old.selection != selection ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}

/// Draggable handle on the rim of the composer circle, in viewport space, and
/// the whole-circle drag that moves the draft itself.
///
/// The handle sits on the left of the rim, or on the right when that would
/// leave the viewport. A press within the handle's radius, tested against
/// the current selection, claims the gesture at once so the canvas does not
/// pan; dragging sets the radius to the pointer's scene distance from the
/// circle centre. A press anywhere else inside the circle instead moves the
/// draft centre (and with it the eventual anchor point) via
/// `ConstellationComposerCubit.moveDraft` — the handle keeps priority where
/// the two hit areas overlap, at the handle's own position. Pointers outside
/// the circle fall through to the canvas.
class ConstellationComposerHandle extends StatelessWidget {
  const ConstellationComposerHandle({
    required this.composer,
    required this.controller,
    super.key,
  });

  final ConstellationComposerCubit composer;
  final GraphController<NodeDetails, EdgeDetails> controller;

  Offset _handleAt(double hit) {
    final selection = composer.selection;
    final centre = controller.sceneToViewportLocal(selection.center);
    final reach = selection.radius * controller.cameraScale;
    final width = controller.viewportSize?.width ?? double.infinity;
    final left = centre + Offset(-reach, 0);
    return left.dx >= hit / 2 || centre.dx + reach > width - hit / 2
        ? left
        : centre + Offset(reach, 0);
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final hit = tt.buttonHeight;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        // Declared first: wins the arena over the center-drag recognizer
        // below when a press lands on the handle itself (see §sweep order
        // in GestureArenaManager — the first member to accept wins).
        _HandleDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_HandleDragRecognizer>(
              _HandleDragRecognizer.new,
              (recognizer) => recognizer
                ..hits = ((local) =>
                    composer.createCubit != null &&
                    (local - _handleAt(hit)).distance <= hit / 2)
                ..onDrag = ((local) => composer.setRadius(
                  (controller.viewportLocalToScene(local) -
                          composer.selection.center)
                      .distance,
                )),
            ),
        // A press anywhere else inside the circle moves the whole draft.
        // Explicitly excludes the handle's own hit area rather than relying
        // on arena sweep order: a press at the exact rim distance would
        // otherwise satisfy both recognizers' hit tests.
        _CenterDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_CenterDragRecognizer>(
              _CenterDragRecognizer.new,
              (recognizer) => recognizer
                ..hits = ((local) {
                  if (composer.createCubit == null) return false;
                  if ((local - _handleAt(hit)).distance <= hit / 2) {
                    return false;
                  }
                  final selection = composer.selection;
                  final scenePoint = controller.viewportLocalToScene(local);
                  return (scenePoint - selection.center).distance <=
                      selection.radius;
                })
                ..onDrag = ((local) => composer.moveDraft(
                  controller.viewportLocalToScene(local),
                )),
            ),
      },
      child: BlocBuilder<ConstellationComposerCubit, RadiusRecipientSelection>(
        bloc: composer,
        builder: (context, selection) => ListenableBuilder(
          listenable: controller.cameraRevision,
          builder: (context, _) {
            if (composer.createCubit == null) {
              return const SizedBox.shrink();
            }
            final at = _handleAt(hit);
            return IgnorePointer(
              child: Stack(
                children: [
                  Positioned(
                    left: at.dx - hit / 2,
                    top: at.dy - hit / 2,
                    width: hit,
                    height: hit,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox.square(dimension: tt.iconSize),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Wins the arena on a press inside [hits], then reports every move.
class _HandleDragRecognizer extends OneSequenceGestureRecognizer {
  late bool Function(Offset local) hits;
  late void Function(Offset local) onDrag;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!hits(event.localPosition)) {
      return;
    }
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onDrag(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'composer radius handle drag';
}

/// Wins the arena on a press inside the composer circle (outside the radius
/// handle's own hit area), then reports every move as the new draft centre.
class _CenterDragRecognizer extends OneSequenceGestureRecognizer {
  late bool Function(Offset local) hits;
  late void Function(Offset local) onDrag;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!hits(event.localPosition)) {
      return;
    }
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onDrag(event.localPosition);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'composer draft centre drag';
}
