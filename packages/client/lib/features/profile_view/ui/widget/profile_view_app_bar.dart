import 'dart:async';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/profile_app_bar_title.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/friends/ui/dialog/friend_remove_dialog.dart';

import '../bloc/profile_view_cubit.dart';
import '../dialog/rename_contact_dialog.dart';

PreferredSizeWidget buildProfileViewAppBar(BuildContext context) {
  final l10n = L10n.of(context)!;
  final screenCubit = context.read<ScreenCubit>();
  final profileViewCubit = context.read<ProfileViewCubit>();

  return TenturaTopBar.of(
    context,
    leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
    title: BlocBuilder<ProfileViewCubit, ProfileViewState>(
      bloc: profileViewCubit,
      buildWhen: (previous, current) => previous.profile != current.profile,
      builder: (context, state) => ProfileAppBarTitle(profile: state.profile),
    ),
    actions: [
      BlocSelector<ProfileViewCubit, ProfileViewState, String>(
        bloc: profileViewCubit,
        selector: (state) => state.profile.id,
        builder: (context, profileId) => ShareCodeIconButton.id(profileId),
      ),
      PopupMenuButton<void>(
        itemBuilder: (menuContext) {
          final state = context.read<ProfileViewCubit>().state;
          final profile = state.profile;
          return <PopupMenuEntry<void>>[
            if (profile.id != GetIt.I<ProfileCubit>().state.profile.id)
              PopupMenuItem<void>(
                onTap: () => unawaited(
                  RenameContactDialog.show(
                    context,
                    profile: profile,
                  ).then((changed) {
                    if (changed ?? false) {
                      unawaited(profileViewCubit.fetch());
                    }
                  }),
                ),
                child: Text(l10n.renameContactMenuItem),
              ),
            if (profile.isFriend)
              PopupMenuItem<void>(
                onTap: () => unawaited(
                  FriendRemoveDialog.show(
                    context,
                    profile: profile,
                    onRemove: profileViewCubit.removeFriend,
                  ),
                ),
                child: Text(l10n.removeFromMyField),
              ),
            PopupMenuItem<void>(
              onTap: () => screenCubit.showComplaint(profile.id),
              child: Text(l10n.buttonComplaint),
            ),
          ];
        },
      ),
    ],
    progress: BlocSelector<ProfileViewCubit, ProfileViewState, bool>(
      bloc: profileViewCubit,
      selector: (state) => state.isLoading,
      builder: TenturaTopBar.loadingBar,
    ),
  );
}
