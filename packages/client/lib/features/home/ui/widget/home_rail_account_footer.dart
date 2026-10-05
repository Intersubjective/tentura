import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'profile_navbar_item.dart';

/// The account at the foot of Home's [NavigationRail] ([NavigationRail.trailing]).
///
/// Laid out like a destination so it reads as part of the rail: a hairline
/// sets it apart from the destinations, the avatar sits in the same 56×32
/// indicator slot as their icons (filled while the profile is open), and the
/// label follows the rail's label metrics — the person's name beside the
/// avatar on an extended rail, «Профиль» under it on a collapsed one. Long
/// press / right click on the avatar switches accounts.
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
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hasAccount =
        GetIt.I.isRegistered<ProfileCubit>() &&
        GetIt.I.isRegistered<AuthCubit>();
    if (!hasAccount) return _build(context, hasAccount: false, name: '');
    return BlocSelector<ProfileCubit, ProfileState, String>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile.displayName,
      builder: (context, name) => _build(context, hasAccount: true, name: name),
    );
  }

  Widget _build(
    BuildContext context, {
    required bool hasAccount,
    required String name,
  }) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final railTheme = NavigationRailTheme.of(context);
    final labelStyle = selected
        ? railTheme.selectedLabelTextStyle
        : railTheme.unselectedLabelTextStyle;

    final avatar = hasAccount
        ? ProfileNavBarItem(selected: selected)
        : Icon(selected ? Icons.person : Icons.person_outline);
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: extended ? _extendedRailWidth : _railWidth,
          child: Divider(
            height: tt.cardGap * 2,
            indent: tt.cardGap,
            endIndent: tt.cardGap,
          ),
        ),
        Semantics(
          button: true,
          selected: selected,
          label: name.isEmpty ? l10n.profile : '${l10n.profile}, $name',
          excludeSemantics: true,
          child: Tooltip(
            message: name.isEmpty ? l10n.profile : name,
            child: InkWell(
              key: footerKey,
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}
