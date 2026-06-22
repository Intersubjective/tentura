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

/// Beacon definition content for the Items tab foldable section.
class BeaconDefinitionBody extends StatelessWidget {
  const BeaconDefinitionBody({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  static const double _thumbSize = 52;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final bodyStyle = TenturaText.body(scheme.onSurfaceVariant);
    final labelStyle = TenturaText.typeLabel(scheme.onSurface);

    final needText = beacon.needSummary?.trim() ?? '';
    final doneWhen = beacon.successCriteria?.trim();
    final requirementTags = resolveCapabilityRequirementTags(beacon.needs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleRow(context, theme, scheme),
        if (beacon.startAt != null || beacon.endAt != null) ...[
          SizedBox(height: tt.rowGap / 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                TenturaIcons.calendar,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${dateFormatYMD(beacon.startAt)} - ${dateFormatYMD(beacon.endAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (beacon.coordinates?.isNotEmpty ?? false) ...[
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
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              label: kIsWeb
                  ? Text(
                      l10n.showOnMap,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : PlaceNameText(
                      coords: beacon.coordinates!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
              onPressed: () => ChooseLocationDialog.show(
                context,
                center: beacon.coordinates,
              ),
            ),
          ),
        ],
        if (beacon.hasNeedSummary && needText.isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          _labeledWrap(
            label: l10n.beaconNeedBriefPrefix,
            body: needText,
            labelStyle: labelStyle,
            bodyStyle: bodyStyle,
          ),
        ],
        if (doneWhen != null && doneWhen.isNotEmpty) ...[
          SizedBox(height: tt.rowGap / 2),
          _labeledWrap(
            label: '${l10n.beaconDoneWhenTitle}:',
            body: doneWhen,
            labelStyle: labelStyle,
            bodyStyle: bodyStyle,
          ),
        ],
        if (requirementTags.isNotEmpty) ...[
          SizedBox(height: tt.rowGap / 2),
          CapabilityRequirementTags(tags: requirementTags),
        ],
        if (beacon.hasPicture) ...[
          SizedBox(height: tt.rowGap),
          _BeaconDefinitionMediaBand(beacon: beacon),
        ],
        if (beacon.description.trim().isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          Text(
            beacon.description.trim(),
            style: ShowMoreText.buildTextStyle(context),
          ),
        ],
      ],
    );
  }

  Widget _titleRow(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final titleStyle = theme.textTheme.titleSmall!.copyWith(
      color: scheme.onSurface,
      decoration: TextDecoration.none,
    );

    final titleText = Text(
      beacon.title,
      style: titleStyle,
      softWrap: true,
    );

    if (!beacon.hasPicture) {
      return titleText;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          child: SizedBox(
            width: _thumbSize,
            height: _thumbSize,
            child: BeaconImage(
              beacon: beacon,
              enableGalleryTap: true,
            ),
          ),
        ),
        SizedBox(width: context.tt.rowGap),
        Expanded(child: titleText),
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

Widget _labeledWrap({
  required String label,
  required String body,
  required TextStyle labelStyle,
  required TextStyle bodyStyle,
}) {
  return SelectableText.rich(
    TextSpan(
      children: [
        TextSpan(text: label, style: labelStyle),
        const TextSpan(text: ' '),
        TextSpan(text: body, style: bodyStyle),
      ],
    ),
  );
}
