import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// «Add fact» button opening a menu: «New fact» / «Pick from available».
class FactAddMenuButton extends StatelessWidget {
  const FactAddMenuButton({
    required this.onNewFact,
    required this.onPickFromAvailable,
    super.key,
  });

  final VoidCallback onNewFact;
  final VoidCallback onPickFromAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: TestIds.key(TestIds.beaconFactsAddNew),
          onPressed: onNewFact,
          child: Text(l10n.beaconFactsAddMenuNew),
        ),
        MenuItemButton(
          key: TestIds.key(TestIds.beaconFactsAddPick),
          onPressed: onPickFromAvailable,
          child: Text(l10n.beaconFactsAddMenuPick),
        ),
      ],
      builder: (context, controller, _) => TenturaCommandButton(
        key: TestIds.key(TestIds.beaconFactsAdd),
        label: l10n.beaconFactsAddFact,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
