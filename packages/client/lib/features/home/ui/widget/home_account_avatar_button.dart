import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'account_menu.dart';
import 'account_nav_bar_avatar.dart';
import 'home_open_profile.dart';
import 'own_paused_chip.dart';

/// The account avatar: opens a unified account menu (profile, settings,
/// account switch, sign out). Long-press and secondary click open the same menu
/// (#1079).
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

  /// If set, invoked when the menu would open (e.g. custom tests). Otherwise
  /// the menu is shown.
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
    return BlocSelector<ProfileCubit, ProfileState, Profile>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile,
      // A fixed glyph; the name (long ones too) goes to the tooltip.
      // #660: the name as shown, read on every build so a server placeholder
      // follows the app language.
      builder: (context, profile) {
        final l10n = L10n.of(context)!;
        final tooltip = profile.shownName.trim().isEmpty
            ? l10n.profile
            : profile.shownName;
        return MenuAnchor(
          menuChildren: buildAccountMenuChildren(context),
          builder: (context, controller, _) {
            void openMenu() {
              if (onPressed != null) {
                onPressed!();
                return;
              }
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            }

            return Semantics(
              button: true,
              label: tooltip,
              hint: l10n.semanticsAccountMenuHint,
              expanded: controller.isOpen,
              container: true,
              excludeSemantics: true,
              child: GestureDetector(
                onSecondaryTap: openMenu,
                behavior: HitTestBehavior.translucent,
                child: IconButton(
                  key: buttonKey,
                  tooltip: tooltip,
                  isSelected: selected,
                  onPressed: openMenu,
                  onLongPress: openMenu,
                  icon: AccountNavBarAvatar(selected: selected),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The account entry for a Home tab's top bar ([TenturaTopBar.account]):
/// compact windows only — wider ones carry it at the rail's foot.
/// While the viewer has paused new requests, a dense [OwnPausedChip] (the
/// pause glyph over the short date, #267) sits beside it, capped at
/// [kTopBarPausedChipWidthShare] of the window so it never crowds the title.
Widget? homeTopBarAccount(BuildContext context) =>
    context.windowClass == WindowClass.compact
    ? Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  MediaQuery.sizeOf(context).width *
                  kTopBarPausedChipWidthShare,
            ),
            child: const OwnPausedChip(dense: true),
          ),
          const HomeAccountAvatarButton(),
        ],
      )
    : null;

/// Share of the window width the top bar's paused chip may take (#267).
const kTopBarPausedChipWidthShare = 0.4;
