import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';
import 'constellation_tag_magnet_control.dart';

/// Screen-sized hit regions over scene-space labels; camera changes move the
/// labels without changing either magnet coordinates or the graph topology.
class ConstellationTagMagnetLayer extends StatelessWidget {
  const ConstellationTagMagnetLayer({
    required this.cubit,
    required this.tags,
    super.key,
  });

  final ConstellationCubit cubit;
  final List<PersonTag> tags;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: cubit.graphController.cameraRevision,
    builder: (context, _) => Stack(
      children: [
        for (final tag in tags)
          if (cubit.tagMagnets[tag.id] case final at?)
            Positioned(
              left: cubit.graphController.sceneToViewportLocal(at).dx,
              top: cubit.graphController.sceneToViewportLocal(at).dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
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
