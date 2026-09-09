import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

class FriendsNavbarItem extends StatelessWidget {
  const FriendsNavbarItem({super.key, this.selected = false});

  /// Kept for parity with sibling navbar items; selection color comes from
  /// [NavigationBar]/[NavigationRail] [IconTheme].
  final bool selected;

  @override
  Widget build(BuildContext context) => Icon(
        TenturaIcons.graph,
        key: ValueKey<bool>(selected),
      );
}
