import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';
import '../utils/constellation_magnet_label_clearance.dart';
import '../utils/constellation_tap_resolver.dart';
import 'constellation_tag_magnet_control.dart';

/// Screen-sized hit regions over scene-space labels; camera changes move the
/// labels without changing either magnet coordinates or the graph topology.
class ConstellationTagMagnetLayer extends StatelessWidget {
  const ConstellationTagMagnetLayer({
    required this.cubit,
    required this.tags,
    required this.frameHolder,
    super.key,
  });

  final ConstellationCubit cubit;
  final List<PersonTag> tags;

  /// Source of the node bodies, labels and overflow chips a magnet must clear.
  final ConstellationPresentationFrameHolder frameHolder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: cubit.graphController.cameraRevision,
    builder: (context, _) => Stack(
      children: [
        for (final tag in tags)
          if (cubit.tagMagnets[tag.id] case final at?)
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _MagnetLabelClearDelegate(
                  center: cubit.graphController.sceneToViewportLocal(at),
                  frameHolder: frameHolder,
                  relayout: cubit.graphController,
                ),
                child: ConstellationTagMagnetControl(
                  actionLabel: L10n.of(context)!.buttonRemove,
                  onAction: () => cubit.removeTagMagnet(tag.id),
                  child: PersonTagChip(
                    glyph: tag.glyph,
                    name: tag.name,
                    colorIndex: tag.color,
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

/// Centres the magnet on its point, then steps it clear of painted obstacles.
class _MagnetLabelClearDelegate extends SingleChildLayoutDelegate {
  _MagnetLabelClearDelegate({
    required this.center,
    required this.frameHolder,
    required Listenable relayout,
  }) : super(relayout: relayout);

  final Offset center;
  final ConstellationPresentationFrameHolder frameHolder;

  @override
  Offset getPositionForChild(Size size, Size childSize) => clearMagnetOfLabels(
    Rect.fromCenter(
      center: center,
      width: childSize.width,
      height: childSize.height,
    ),
    // The overlay publishes the current geometry during build. Read it at
    // layout time, after all siblings have built, including on graph motion.
    [
      ...?frameHolder.frame?.bodies.values,
      ...?frameHolder.frame?.labels.values,
      ...?frameHolder.frame?.chips.values,
    ],
    bounds: Offset.zero & size,
  ).topLeft;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  bool shouldRelayout(_MagnetLabelClearDelegate old) => true;
}
