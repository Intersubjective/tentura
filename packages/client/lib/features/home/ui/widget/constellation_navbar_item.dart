import 'package:flutter/material.dart';

import 'package:tentura/ui/test_ids.dart';

/// Constellation tab icon — deliberately badge-incapable (§9.2 anti-feed).
class ConstellationNavbarItem extends StatelessWidget {
  const ConstellationNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: TestIds.constellationNavItem,
    child: Icon(
      key: TestIds.key(TestIds.constellationNavItem),
      selected ? Icons.hub : Icons.hub_outlined,
    ),
  );
}
