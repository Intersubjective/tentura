import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/auth/ui/dialog/sign_out_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// Items for the unified account menu (#1079): profile, settings, sign out.
List<Widget> buildAccountMenuChildren(BuildContext context) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final profile = GetIt.I<ProfileCubit>().state.profile;
  final theme = Theme.of(context);

  void closeMenu() => MenuController.maybeOf(context)?.close();

  return [
    MenuItemButton(
      style: _menuItemStyle(context),
      onPressed: () {
        closeMenu();
        unawaited(GetIt.I<AppNavigator>().openMyProfile());
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            SelfAwareAvatar.small(profile: profile),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.shownName.trim().isEmpty
                        ? l10n.profile
                        : profile.shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.accountMenuViewProfile,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    MenuItemButton(
      style: _menuItemStyle(context),
      onPressed: () {
        closeMenu();
        GetIt.I<ScreenCubit>().showSettings();
      },
      child: SizedBox(
        width: double.infinity,
        height: kMinInteractiveDimension,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.labelSettings,
            style: theme.textTheme.titleSmall,
          ),
        ),
      ),
    ),
    const Divider(height: 1),
    MenuItemButton(
      style: _menuItemStyle(context),
      onPressed: () async {
        closeMenu();
        await confirmAndSignOut(context);
      },
      child: SizedBox(
        width: double.infinity,
        height: kMinInteractiveDimension,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.logout,
            style: theme.textTheme.titleSmall?.copyWith(color: tt.danger),
          ),
        ),
      ),
    ),
  ];
}

ButtonStyle _menuItemStyle(BuildContext context) {
  final tt = context.tt;
  return ButtonStyle(
    padding: WidgetStateProperty.all(
      EdgeInsets.symmetric(horizontal: tt.rowGap, vertical: tt.tightGap),
    ),
    minimumSize: WidgetStateProperty.all(
      const Size(0, kMinInteractiveDimension),
    ),
  );
}
