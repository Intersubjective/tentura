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
class ConstellationTagMagnetLayer extends StatefulWidget {
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
  State<ConstellationTagMagnetLayer> createState() =>
      _ConstellationTagMagnetLayerState();
}

class _ConstellationTagMagnetLayerState
    extends State<ConstellationTagMagnetLayer> {
  final _controlSizes = <String, Size>{};
  late VoidCallback _detachControlSizes;

  @override
  void initState() {
    super.initState();
    _attachControlSizes();
  }

  @override
  void didUpdateWidget(ConstellationTagMagnetLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit) {
      _detachControlSizes();
      _controlSizes.clear();
      _attachControlSizes();
    }
  }

  void _attachControlSizes() {
    _detachControlSizes = widget.cubit.attachTagMagnetControlSizes(
      () => _controlSizes,
    );
  }

  @override
  void dispose() {
    _detachControlSizes();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.cubit.graphController.cameraRevision,
    builder: (context, _) {
      final cubit = widget.cubit;
      final magnets = cubit.tagMagnets;
      final shownTags = [
        for (final tag in widget.tags)
          if (magnets.containsKey(tag.id)) tag,
      ];
      final shownIds = {for (final tag in shownTags) tag.id};
      _controlSizes.removeWhere((id, _) => !shownIds.contains(id));
      return Stack(
        children: [
          for (final tag in shownTags)
            if (magnets[tag.id] case final at?)
              Positioned.fill(
                key: ValueKey(tag.id),
                child: CustomSingleChildLayout(
                  delegate: _MagnetLabelClearDelegate(
                    center: cubit.graphController.sceneToViewportLocal(at),
                    frameHolder: widget.frameHolder,
                    onSize: (size) => _controlSizes[tag.id] = size,
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
      );
    },
  );
}

/// Centres the magnet on its point, then steps it clear of painted obstacles.
class _MagnetLabelClearDelegate extends SingleChildLayoutDelegate {
  _MagnetLabelClearDelegate({
    required this.center,
    required this.frameHolder,
    required this.onSize,
    required Listenable relayout,
  }) : super(relayout: relayout);

  final Offset center;
  final ConstellationPresentationFrameHolder frameHolder;
  final ValueChanged<Size> onSize;

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    onSize(childSize);
    return clearMagnetOfLabels(
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
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  bool shouldRelayout(_MagnetLabelClearDelegate old) => true;
}
