import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/beacon_image_gallery.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';
import 'package:tentura/ui/widget/tentura_selection_area.dart';

/// Beacon definition content for the HUD fold (needs, media, description).
class BeaconDefinitionBody extends StatelessWidget {
  const BeaconDefinitionBody({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final textStyle = TenturaText.hudBodySmall(scheme.onSurface);
    final mutedHudStyle = TenturaText.hudBodySmall(tt.textMuted);
    final requirementTags = resolveCapabilityRequirementTags(beacon.needs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (requirementTags.isNotEmpty) ...[
          CapabilityRequirementTags(
            tags: requirementTags,
            showHeading: false,
            labelStyle: mutedHudStyle,
          ),
        ],
        if (beacon.hasPicture) ...[
          if (requirementTags.isNotEmpty) SizedBox(height: tt.rowGap),
          _BeaconDefinitionMediaBand(beacon: beacon),
        ],
        if (beacon.description.trim().isNotEmpty) ...[
          if (requirementTags.isNotEmpty || beacon.hasPicture)
            SizedBox(height: tt.rowGap),
          TenturaSelectionArea(
            child: Text.rich(
              buildRoomMessageAnnotatedBodySpan(
                data: beacon.description.trim(),
                textStyle: textStyle,
                annotations: buildUrlAnnotations(linkColor: tt.info),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _BeaconDefinitionMediaBand extends StatelessWidget {
  const _BeaconDefinitionMediaBand({required this.beacon});

  final Beacon beacon;

  static double _mediaHeight(WindowClass windowClass) => switch (windowClass) {
    WindowClass.compact => 200,
    WindowClass.regular => 260,
    WindowClass.expanded => 320,
  };

  static double? _mediaMaxWidth(WindowClass windowClass) =>
      switch (windowClass) {
        WindowClass.compact => null,
        WindowClass.regular => 560,
        WindowClass.expanded => 720,
      };

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowClass = windowClassForWidth(constraints.maxWidth);
        final mediaHeight = _mediaHeight(windowClass);
        final mediaMaxWidth = _mediaMaxWidth(windowClass);

        Widget media;
        if (beacon.displayImages.length > 1) {
          media = BeaconImageGallery(
            beacon: beacon,
            maxHeight: mediaHeight,
          );
        } else {
          media = ClipRRect(
            borderRadius: BorderRadius.circular(tt.cardRadius),
            child: ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: SizedBox(
                height: mediaHeight,
                width: double.infinity,
                child: BeaconImage(
                  beacon: beacon,
                  boxFit: BoxFit.contain,
                  enableGalleryTap: true,
                ),
              ),
            ),
          );
        }

        if (mediaMaxWidth == null) {
          return media;
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: mediaMaxWidth),
            child: media,
          ),
        );
      },
    );
  }
}
