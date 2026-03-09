import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/rating_indicator.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/favorites/ui/widget/beacon_pin_icon_button.dart';
import 'package:tentura/features/like/ui/widget/like_control.dart';
import 'package:tentura/features/polling/ui/widget/poll_button.dart';

class BeaconTileControl extends StatelessWidget {
  const BeaconTileControl({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      // Graph View
      IconButton(
        icon: const Icon(TenturaIcons.graph),
        onPressed: beacon.myVote < 0
            ? null
            : () => context.read<ScreenCubit>().showGraphFor(beacon.id),
      ),

      // Share
      ShareCodeIconButton.id(beacon.id),

      // Favorite
      BeaconPinIconButton(
        key: ValueKey(beacon.author),
        beacon: beacon,
      ),

      // Poll button
      if (beacon.hasPolling) PollButton(polling: beacon.polling),

      const Spacer(),

      // Rating bar
      Padding(
        padding: kPaddingSmallH,
        child: RatingIndicator(
          key: ValueKey(beacon.score),
          score: beacon.score,
        ),
      ),

      // Like\Dislike
      LikeControl(
        key: ValueKey(beacon),
        entity: beacon,
      ),
    ],
  );
}
