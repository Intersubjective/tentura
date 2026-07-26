import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_location_actions.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/beacon_image_gallery.dart';
import 'package:tentura/ui/widget/url_link_annotations.dart';

/// Beacon definition content for the HUD fold (schedule, need, media, description).
class BeaconDefinitionBody extends StatelessWidget {
  const BeaconDefinitionBody({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  static const double _metaIconSize = 18;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final textStyle = TenturaText.hudBodySmall(scheme.onSurface);
    final mutedHudStyle = TenturaText.hudBodySmall(tt.textMuted);
    final metaIconColor = scheme.onSurfaceVariant;
    final requirementTags = resolveCapabilityRequirementTags(beacon.needs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (beacon.startAt != null || beacon.endAt != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                TenturaIcons.calendar,
                size: _metaIconSize,
                color: metaIconColor,
              ),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: Text(
                  '${dateFormatYMD(beacon.startAt)} - ${dateFormatYMD(beacon.endAt)}',
                  style: textStyle,
                ),
              ),
            ],
          ),
        ],
        if (beacon.coordinates?.isNotEmpty ?? false) ...[
          if (beacon.startAt != null || beacon.endAt != null)
            SizedBox(height: tt.rowGap / 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                TenturaIcons.location,
                size: _metaIconSize,
                color: metaIconColor,
              ),
              label: Text(
                _locationLabel(beacon, l10n),
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => showBeaconLocationActions(context, beacon),
            ),
          ),
        ],
        if (requirementTags.isNotEmpty) ...[
          SizedBox(height: tt.rowGap / 2),
          CapabilityRequirementTags(
            tags: requirementTags,
            showHeading: false,
            labelStyle: mutedHudStyle,
          ),
        ],
        if (beacon.hasPicture) ...[
          SizedBox(height: tt.rowGap),
          _BeaconDefinitionMediaBand(beacon: beacon),
        ],
        if (beacon.description.trim().isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          Text.rich(
            buildRoomMessageAnnotatedBodySpan(
              data: beacon.description.trim(),
              textStyle: textStyle,
              annotations: buildUrlAnnotations(linkColor: tt.info),
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
            child: SizedBox(
              height: mediaHeight,
              width: double.infinity,
              child: BeaconImage(
                beacon: beacon,
                enableGalleryTap: true,
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

String _locationLabel(Beacon beacon, L10n l10n) {
  final label = beacon.addressLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return l10n.showOnMap;
}
