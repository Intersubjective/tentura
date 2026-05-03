import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/beacon_image_gallery.dart';
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
    this.showTitle = true,
    this.onClickTag,
    /// When true, description and tags render before image block (operational layouts).
    this.descriptionBeforeMedia = false,
    /// Caps gallery / hero image height when set.
    this.mediaMaxHeight,
    /// When true with multiple images, passes [mediaMaxHeight] into [BeaconImageGallery].
    this.compactImageGallery = false,
    super.key,
  });

  final Beacon beacon;
  final bool isTitleLarge;
  final bool isShowMoreEnabled;
  final bool isShowBeaconEnabled;
  final bool showTitle;
  final TagClickCallback? onClickTag;
  final bool descriptionBeforeMedia;
  final double? mediaMaxHeight;
  final bool compactImageGallery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final useGallery = !isShowBeaconEnabled && beacon.images.length > 1;
    final maxH = mediaMaxHeight;

    final mediaBlock = useGallery && beacon.hasPicture
        ? Padding(
            padding: kPaddingSmallT,
            child: BeaconImageGallery(
              beacon: beacon,
              maxHeight: compactImageGallery ? maxH : null,
            ),
          )
        : GestureDetector(
            onTap: isShowBeaconEnabled
                ? () => context.read<ScreenCubit>().showBeacon(beacon.id)
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (beacon.hasPicture)
                  Padding(
                    padding: kPaddingSmallT,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: maxH != null
                          ? SizedBox(
                              height: maxH,
                              width: double.infinity,
                              child: BeaconImage(
                                beacon: beacon,
                                enableGalleryTap: !isShowBeaconEnabled,
                              ),
                            )
                          : BeaconImage(
                              beacon: beacon,
                              enableGalleryTap: !isShowBeaconEnabled,
                            ),
                    ),
                  ),
              ],
            ),
          );

    final titleBlock = showTitle
        ? GestureDetector(
            onTap: isShowBeaconEnabled
                ? () => context.read<ScreenCubit>().showBeacon(beacon.id)
                : null,
            child: Padding(
              padding: kPaddingT,
              child: Text(
                beacon.title,
                maxLines: 1,
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: (isTitleLarge
                        ? theme.textTheme.headlineLarge
                        : theme.textTheme.headlineMedium)
                    ?.copyWith(
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final timerangeBlock = beacon.startAt != null || beacon.endAt != null
        ? Padding(
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
          )
        : const SizedBox.shrink();

    final descriptionBlock = beacon.description.isNotEmpty
        ? Padding(
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
          )
        : const SizedBox.shrink();

    final geoBlock = (beacon.coordinates?.isNotEmpty ?? false)
        ? Align(
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
          )
        : const SizedBox.shrink();

    final tagsBlock = const SizedBox.shrink();
    // final tagsBlock = beacon.tags.isNotEmpty
    //     ? Wrap(
    //         children: [
    //           for (final tag in beacon.tags)
    //             TextButton(
    //               onPressed: () => onClickTag?.call(tag),
    //               style: TextButton.styleFrom(
    //                 padding: kPaddingSmallH,
    //                 visualDensity: VisualDensity.compact,
    //               ),
    //               child: Text('#$tag'),
    //             ),
    //         ],
    //       )
    //     : const SizedBox.shrink();

    final coreColumn = descriptionBeforeMedia
        ? <Widget>[
            titleBlock,
            timerangeBlock,
            descriptionBlock,
            geoBlock,
            tagsBlock,
            mediaBlock,
          ]
        : <Widget>[
            mediaBlock,
            titleBlock,
            timerangeBlock,
            descriptionBlock,
            geoBlock,
            tagsBlock,
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: coreColumn,
    );
  }
}
