import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

class ProfileAppBar extends StatelessWidget {
  const ProfileAppBar({
    required this.profile,
    super.key,
  });

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;

    return SliverInboxStyleAppBar(
      leading: PopupMenuButton<String>(
        icon: const Icon(Icons.menu),
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onSelected: (value) {
          if (value == 'edit') {
            context.read<ScreenCubit>().showProfileEditor();
          } else if (value == 'rating') {
            context.read<ScreenCubit>().showRating();
          }
        },
        itemBuilder: (menuContext) => [
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 22,
                  color: Theme.of(menuContext).colorScheme.onSurface,
                ),
                const SizedBox(width: 12),
                Text(l10n.profileOverflowEdit),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'rating',
            child: Row(
              children: [
                Icon(
                  Icons.leaderboard,
                  size: 22,
                  color: Theme.of(menuContext).colorScheme.onSurface,
                ),
                const SizedBox(width: 12),
                Text(l10n.rating),
              ],
            ),
          ),
        ],
      ),
      title: Row(
        children: [
          SelfAwareAvatar(
            profile: profile,
            size: 32,
            withRating: false,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.title.isEmpty ? l10n.noName : profile.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  profile.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.72),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ShareCodeIconButton.id(profile.id),
        ),
      ],
    );
  }
}
