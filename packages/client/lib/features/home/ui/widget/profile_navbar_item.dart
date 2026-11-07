import 'package:flutter/material.dart';

import 'account_nav_bar_avatar.dart';

/// Compact account glyph for Home chrome (see [AccountNavBarAvatar]).
///
/// Kept as a thin alias for call sites that still use this name (#1079).
class ProfileNavBarItem extends StatelessWidget {
  const ProfileNavBarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) => AccountNavBarAvatar(selected: selected);
}
