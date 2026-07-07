import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/dialog/sign_out_dialog.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

PreferredSizeWidget buildProfileAppBar(
  BuildContext context, {
  required Profile profile,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final l10n = L10n.of(context)!;
  final tt = context.tt;

  return TenturaTopBar.of(
    context,
    key: Key('ProfileAppBar:${profile.id}'),
    tone: TenturaTopBarTone.primary,
    title: Row(
      children: [
        SelfAwareAvatar.medium(
          profile: profile,
          size: tt.metadataAvatarSize + tt.tightGap * 2,
        ),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.displayName.isEmpty ? l10n.noName : profile.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (profile.handle.isNotEmpty)
                Text(
                  '@${profile.handle}',
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
      IconButton(
        tooltip: l10n.profileOverflowEdit,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: tt.buttonHeight,
          minHeight: tt.buttonHeight,
        ),
        onPressed: () => context.read<ScreenCubit>().showProfileEditor(),
        icon: const Icon(Icons.edit_outlined),
      ),
      ShareCodeIconButton.id(profile.id),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: tt.buttonHeight,
          minHeight: tt.buttonHeight,
        ),
        onSelected: (value) {
          switch (value) {
            case 'rating':
              context.read<ScreenCubit>().showRating();
            case 'logout':
              unawaited(confirmAndSignOut(context));
          }
        },
        itemBuilder: (menuContext) => [
          PopupMenuItem<String>(
            value: 'rating',
            child: Row(
              children: [
                Icon(
                  Icons.leaderboard,
                  size: tt.iconSize,
                  color: Theme.of(menuContext).colorScheme.onSurface,
                ),
                SizedBox(width: tt.rowGap),
                Text(l10n.rating),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                Icon(
                  Icons.logout,
                  size: tt.iconSize,
                  color: Theme.of(menuContext).colorScheme.onSurface,
                ),
                SizedBox(width: tt.rowGap),
                Text(l10n.logout),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
