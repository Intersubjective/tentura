import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'account_menu.dart';
import 'account_nav_bar_avatar.dart';
import 'own_paused_chip.dart';

/// The account at the foot of Home's [NavigationRail] ([NavigationRail.trailing]).
///
/// Laid out like a destination so it reads as part of the rail: a hairline
/// sets it apart from the destinations, the avatar sits in the same 56×32
/// indicator slot as their icons (filled while the profile is open), and the
/// label follows the rail's label metrics — the person's name beside the
/// avatar on an extended rail, «Профиль» under it on a collapsed one. Tap,
/// long-press and secondary click open the unified account menu (#1079).
class HomeRailAccountFooter extends StatelessWidget {
  const HomeRailAccountFooter({
    required this.extended,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  static const footerKey = Key('home-rail-account');

  /// Material rail widths and indicator size (NavigationRail defaults).
  static const _railWidth = 80.0;
  static const _extendedRailWidth = 256.0;
  static const _indicatorSize = Size(56, 32);

  final bool extended;
  final bool selected;

  /// Used when account DI is missing (tests): opens profile / Me tab.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasAccount =
        GetIt.I.isRegistered<ProfileCubit>() &&
        GetIt.I.isRegistered<AuthCubit>();
    if (!hasAccount) {
      return _RailAccountBody(
        extended: extended,
        selected: selected,
        name: '',
        hasAccount: false,
        onActivate: onPressed,
      );
    }
    return BlocSelector<ProfileCubit, ProfileState, Profile>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile,
      builder: (context, profile) => _RailAccountBody(
        extended: extended,
        selected: selected,
        name: profile.shownName.trim(),
        hasAccount: true,
        onActivate: onPressed,
      ),
    );
  }
}

class _RailAccountBody extends StatelessWidget {
  const _RailAccountBody({
    required this.extended,
    required this.selected,
    required this.name,
    required this.hasAccount,
    required this.onActivate,
  });

  final bool extended;
  final bool selected;
  final String name;
  final bool hasAccount;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    if (!hasAccount) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: extended
                ? HomeRailAccountFooter._extendedRailWidth
                : HomeRailAccountFooter._railWidth,
            child: Divider(
              height: tt.cardGap * 2,
              indent: tt.cardGap,
              endIndent: tt.cardGap,
            ),
          ),
          _RailAccountVisual(
            extended: extended,
            selected: selected,
            name: name,
            footerKey: HomeRailAccountFooter.footerKey,
            semanticsLabel: name.isEmpty
                ? l10n.profile
                : '${l10n.profile}, $name',
            onActivate: onActivate,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.cardGap),
          child: OwnPausedChip(iconOnly: !extended),
        ),
        SizedBox(
          width: extended
              ? HomeRailAccountFooter._extendedRailWidth
              : HomeRailAccountFooter._railWidth,
          child: Divider(
            height: tt.cardGap * 2,
            indent: tt.cardGap,
            endIndent: tt.cardGap,
          ),
        ),
        MenuAnchor(
          menuChildren: buildAccountMenuChildren(context),
          builder: (context, controller, _) {
            void openMenu() {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            }

            return _RailAccountVisual(
              extended: extended,
              selected: selected,
              name: name,
              footerKey: HomeRailAccountFooter.footerKey,
              semanticsLabel: name.isEmpty
                  ? l10n.profile
                  : '${l10n.profile}, $name',
              semanticsHint: l10n.semanticsAccountMenuHint,
              menuOpenBuilder: (_) => controller.isOpen,
              onActivate: openMenu,
            );
          },
        ),
      ],
    );
  }
}

/// Shared chrome: indicator slot, label, semantics, hit targets.
class _RailAccountVisual extends StatelessWidget {
  const _RailAccountVisual({
    required this.extended,
    required this.selected,
    required this.name,
    required this.footerKey,
    required this.semanticsLabel,
    required this.onActivate,
    this.semanticsHint,
    this.menuOpenBuilder,
  });

  final bool extended;
  final bool selected;
  final String name;
  final Key footerKey;
  final String semanticsLabel;
  final String? semanticsHint;
  final bool Function(BuildContext)? menuOpenBuilder;
  final VoidCallback onActivate;

  static const _railWidth = HomeRailAccountFooter._railWidth;
  static const _extendedRailWidth = HomeRailAccountFooter._extendedRailWidth;
  static const _indicatorSize = HomeRailAccountFooter._indicatorSize;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final railTheme = NavigationRailTheme.of(context);
    final labelStyle = selected
        ? railTheme.selectedLabelTextStyle
        : railTheme.unselectedLabelTextStyle;

    final avatar = AccountNavBarAvatar(selected: selected);
    final indicator = Container(
      width: _indicatorSize.width,
      height: _indicatorSize.height,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: selected
            ? railTheme.indicatorColor ?? theme.colorScheme.secondaryContainer
            : Colors.transparent,
      ),
      child: avatar,
    );

    final label = extended && name.isNotEmpty ? name : l10n.profile;

    final Widget body = extended
        ? SizedBox(
            width: _extendedRailWidth,
            height: kMinInteractiveDimension + tt.tightGap,
            child: Row(
              children: [
                SizedBox(
                  width: _railWidth,
                  child: Center(child: indicator),
                ),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                SizedBox(width: tt.screenHPadding),
              ],
            ),
          )
        : Padding(
            padding: EdgeInsets.symmetric(vertical: tt.tightGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                indicator,
                SizedBox(height: tt.tightGap),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ],
            ),
          );

    final menuOpen = menuOpenBuilder?.call(context) ?? false;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      expanded: menuOpenBuilder != null ? menuOpen : null,
      label: semanticsLabel,
      hint: semanticsHint,
      child: Tooltip(
        message: name.isEmpty ? l10n.profile : name,
        excludeFromSemantics: true,
        child: InkWell(
          key: footerKey,
          onTap: onActivate,
          onLongPress: onActivate,
          onSecondaryTap: onActivate,
          customBorder: const StadiumBorder(),
          child: ExcludeSemantics(child: body),
        ),
      ),
    );
  }
}
