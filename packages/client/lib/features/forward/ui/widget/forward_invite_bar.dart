import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Pinned "invite new person" / "clear selection" affordance shown above
/// the forward tab content.
///
/// While nothing is selected it offers the invite action; once at least
/// one recipient is picked, it swaps in place to a "clear selection"
/// action instead of coexisting with it, so the row always carries a
/// single, high-visibility affordance rather than two competing ones.
class ForwardInviteBar extends StatelessWidget {
  const ForwardInviteBar({
    required this.hasSelection,
    required this.onInvite,
    required this.onClearSelection,
    super.key,
  });

  /// Matches [TenturaCommandButton]'s own fixed compact height.
  static const double buttonHeight = 40;

  final bool hasSelection;
  final VoidCallback onInvite;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final testId = hasSelection
        ? TestIds.forwardClearSelection
        : TestIds.forwardInviteNewPerson;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.rowGap,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          identifier: testId,
          button: true,
          child: TenturaCommandButton(
            key: TestIds.key(testId),
            label: hasSelection
                ? l10n.forwardClearSelection
                : l10n.forwardInviteNewPerson,
            icon: Icon(
              hasSelection ? Icons.deselect : Icons.person_add_alt_1_outlined,
            ),
            onPressed: hasSelection ? onClearSelection : onInvite,
          ),
        ),
      ),
    );
  }
}
