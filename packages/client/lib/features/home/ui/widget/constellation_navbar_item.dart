import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_icons.dart';
import 'package:tentura/ui/test_ids.dart';

/// Field (Constellation) tab icon — deliberately badge-incapable (§9.2 anti-feed).
///
/// Uses the Tentura brand glyph ([TenturaIcons.graph]); selection chrome comes
/// from the parent [IconTheme] (no outlined variant).
class ConstellationNavbarItem extends StatelessWidget {
  const ConstellationNavbarItem({super.key, this.selected = false});

  /// API parity with sibling navbar items; unused — one glyph only.
  // ignore: unused_field
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: TestIds.constellationNavItem,
    child: Icon(
      key: TestIds.key(TestIds.constellationNavItem),
      TenturaIcons.graph,
    ),
  );
}
