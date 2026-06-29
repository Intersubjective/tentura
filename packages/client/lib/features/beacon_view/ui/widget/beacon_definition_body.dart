import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/capability/ui/widget/capability_requirement_tags.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';
import 'package:tentura/features/geo/ui/widget/place_name_text.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/beacon_image_gallery.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

/// Beacon definition content for the HUD fold (schedule, need, media, description).
class BeaconDefinitionBody extends StatelessWidget {
  const BeaconDefinitionBody({
    required this.beacon,
    this.includeNeedSummary = true,
    super.key,
  });

  final Beacon beacon;

  /// When false, omits the need line (shown elsewhere, e.g. HUD collapsed row).
  final bool includeNeedSummary;

  static const double _metaIconSize = 18;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final textStyle = TenturaText.bodySmall(scheme.onSurface).copyWith(
      height: 1.25,
    );
    final metaIconColor = scheme.onSurfaceVariant;

    final needText = beacon.needSummary?.trim() ?? '';
    final doneWhen = beacon.successCriteria?.trim();
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
              label: kIsWeb
                  ? Text(l10n.showOnMap, style: textStyle)
                  : PlaceNameText(
                      coords: beacon.coordinates!,
                      style: textStyle,
                    ),
              onPressed: () => ChooseLocationDialog.show(
                context,
                center: beacon.coordinates,
              ),
            ),
          ),
        ],
        if (includeNeedSummary &&
            beacon.hasNeedSummary &&
            needText.isNotEmpty) ...[
          if (beacon.startAt != null ||
              beacon.endAt != null ||
              (beacon.coordinates?.isNotEmpty ?? false))
            SizedBox(height: tt.rowGap / 2),
          _labeledLine(
            label: l10n.beaconNeedBriefPrefix,
            body: needText,
            style: textStyle,
          ),
        ],
        if (doneWhen != null && doneWhen.isNotEmpty) ...[
          SizedBox(height: tt.rowGap / 2),
          _labeledLine(
            label: '${l10n.beaconDoneWhenTitle}:',
            body: doneWhen,
            style: textStyle,
          ),
        ],
        if (requirementTags.isNotEmpty) ...[
          SizedBox(height: tt.rowGap / 2),
          CapabilityRequirementTags(
            tags: requirementTags,
            showHeading: false,
          ),
        ],
        if (beacon.hasPicture) ...[
          SizedBox(height: tt.rowGap),
          _BeaconDefinitionMediaBand(beacon: beacon),
        ],
        if (beacon.description.trim().isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          ShowMoreText(
            beacon.description.trim(),
            style: textStyle,
            colorClickableText: scheme.primary,
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

  static double? _mediaMaxWidth(WindowClass windowClass) => switch (windowClass) {
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
        if (beacon.images.length > 1) {
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

Widget _labeledLine({
  required String label,
  required String body,
  required TextStyle style,
}) {
  return SelectableText.rich(
    TextSpan(
      children: [
        TextSpan(text: label, style: style),
        const TextSpan(text: ' '),
        TextSpan(text: body, style: style),
      ],
    ),
  );
}
