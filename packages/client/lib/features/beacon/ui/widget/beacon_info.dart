import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import 'package:tentura/features/geo/ui/widget/place_name_text.dart';
import 'package:tentura/features/geo/ui/dialog/choose_location_dialog.dart';

typedef TagClickCallback = void Function(String);

class BeaconInfo extends StatelessWidget {
  const BeaconInfo({
    required this.beacon,
    required this.isShowBeaconEnabled,
    this.isShowMoreEnabled = true,
    this.isTitleLarge = false,
    this.onClickTag,
    super.key,
  });

  final Beacon beacon;
  final bool isTitleLarge;
  final bool isShowMoreEnabled;
  final bool isShowBeaconEnabled;
  final TagClickCallback? onClickTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: isShowBeaconEnabled
              ? () => context.read<ScreenCubit>().showBeacon(beacon.id)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Beacon Image
              if (beacon.hasPicture)
                Padding(
                  padding: kPaddingSmallT,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: BeaconImage(beacon: beacon),
                  ),
                ),

              // Beacon Title
              Padding(
                padding: kPaddingT,
                child: Text(
                  beacon.title,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (isTitleLarge
                              ? theme.textTheme.headlineLarge
                              : theme.textTheme.headlineMedium)
                          ?.copyWith(
                            decoration: TextDecoration.underline,
                          ),
                ),
              ),
            ],
          ),
        ),

        //Beacon Timerange
        if (beacon.startAt != null || beacon.endAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpacingSmall),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  TenturaIcons.calendar,
                  size: 18,
                ),
                Text(
                  ' ${dateFormatYMD(beacon.startAt)}'
                  ' - ${dateFormatYMD(beacon.endAt)}',
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),

        // Beacon Description
        if (beacon.description.isNotEmpty)
          Padding(
            padding: kPaddingSmallT,
            child: isShowMoreEnabled
                ? ShowMoreText(
                    beacon.description,
                    style: ShowMoreText.buildTextStyle(context),
                    colorClickableText: Theme.of(context).colorScheme.primary,
                  )
                : Text(
                    beacon.description,
                    style: ShowMoreText.buildTextStyle(context),
                  ),
          ),

        // Beacon Geolocation
        if (beacon.coordinates?.isNotEmpty ?? false)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(TenturaIcons.location),
              label: kIsWeb
                  ? Text(l10n.showOnMap)
                  : PlaceNameText(
                      coords: beacon.coordinates!,
                      style: theme.textTheme.bodySmall,
                    ),
              onPressed: () => ChooseLocationDialog.show(
                context,
                center: beacon.coordinates,
              ),
            ),
          ),

        // Tags
        if (beacon.tags.isNotEmpty)
          Wrap(
            children: [
              for (final tag in beacon.tags)
                TextButton(
                  onPressed: () => onClickTag?.call(tag),
                  style: TextButton.styleFrom(
                    padding: kPaddingSmallH,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text('#$tag'),
                ),
            ],
          ),
      ],
    );
  }
}
