import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'profile_navbar_item.dart';

/// The account avatar: opens the viewer's profile (Home's Me tab), and on a
/// long press or secondary click switches accounts.
///
/// Me is not a navigation destination. The avatar sits at the bottom of the
/// rail on wide windows and at the end of each Home tab's top bar on compact
/// ones, where every product puts the account.
class HomeAccountAvatarButton extends StatelessWidget {
  const HomeAccountAvatarButton({
    this.selected = false,
    this.onPressed,
    super.key,
  });

  static const buttonKey = Key('home-account-avatar');

  /// The profile is open: the avatar carries the selection ring.
  final bool selected;

  /// Defaults to [openMyProfile].
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // Without the account cubits (a route rendered outside the app's DI,
    // isolated tests) the avatar falls back to a plain glyph.
    if (!GetIt.I.isRegistered<ProfileCubit>() ||
        !GetIt.I.isRegistered<AuthCubit>()) {
      return IconButton(
        key: buttonKey,
        tooltip: L10n.of(context)!.profile,
        isSelected: selected,
        onPressed: onPressed ?? () => openMyProfile(context),
        icon: Icon(selected ? Icons.person : Icons.person_outline),
      );
    }
    return BlocSelector<ProfileCubit, ProfileState, String>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile.displayName,
      // A fixed glyph; the name (long ones too) goes to the tooltip.
      builder: (context, name) => IconButton(
        key: buttonKey,
        tooltip: name.isEmpty ? L10n.of(context)!.profile : name,
        isSelected: selected,
        onPressed: onPressed ?? () => openMyProfile(context),
        icon: ProfileNavBarItem(selected: selected),
      ),
    );
  }
}

/// The account entry for a Home tab's top bar ([TenturaTopBar.account]):
/// compact windows only — wider ones carry it at the rail's foot.
Widget? homeTopBarAccount(BuildContext context) =>
    context.windowClass == WindowClass.compact
    ? const HomeAccountAvatarButton()
    : null;

/// Opens Home's Me tab, from inside Home or from a route pushed above it.
void openMyProfile(BuildContext context) {
  final root = context.router.root;
  root
      .innerRouterOf<TabsRouter>(HomeRoute.name)
      ?.setActiveIndex(HomeTabSpec.forTab(HomeTab.me).index);
  if (root.current.name != HomeRoute.name) {
    unawaited(root.replacePath(kPathProfile));
  }
}
