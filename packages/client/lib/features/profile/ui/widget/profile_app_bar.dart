import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/profile_app_bar_title.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

class ProfileAppBar extends StatelessWidget {
  const ProfileAppBar({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) => SliverAppBar(
    automaticallyImplyLeading: false,
    floating: true,
    snap: true,
    title: ProfileAppBarTitle(
      key: ObjectKey(profile),
      profile: profile,
    ),
    actions: [
      // Edit
      IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: context.read<ScreenCubit>().showProfileEditor,
      ),

      // Show Rating
      IconButton(
        icon: const Icon(Icons.leaderboard),
        onPressed: context.read<ScreenCubit>().showRating,
      ),

      // Share
      Padding(
        padding: const EdgeInsets.only(
          right: kSpacingSmall,
        ),
        child: ShareCodeIconButton.id(profile.id),
      ),
    ],
  );
}
