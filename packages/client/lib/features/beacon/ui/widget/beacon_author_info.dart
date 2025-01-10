import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

class BeaconAuthorInfo extends StatelessWidget {
  const BeaconAuthorInfo({
    required this.author,
    super.key,
  });

  final Profile author;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => context.pushRoute(
        ProfileViewRoute(id: author.id),
      ),
      child: Row(
        children: [
          // Avatar
          Padding(
            padding: kPaddingAllS,
            child: AvatarRated(profile: author),
          ),

          // User displayName
          GestureDetector(
            onTap: () => context.pushRoute(
              ProfileViewRoute(id: author.id),
            ),
            child: Text(
              author.title,
              style: textTheme.headlineMedium,
            ),
          ),

          // An Eye
          Padding(
            padding: kPaddingH,
            child: Icon(
              author.isSeeingMe
                  ? Icons.remove_red_eye
                  : Icons.remove_red_eye_outlined,
            ),
          ),
        ],
      ),
    );
  }
}
