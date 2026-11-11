import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Pinned "invite new person" affordance shown above the forward tab
/// content.
///
/// Inviting stays available once recipients are picked (the invite leaves the
/// selection intact); a compact "clear selection" icon joins it then.
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.rowGap,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              identifier: TestIds.forwardInviteNewPerson,
              button: true,
              child: TenturaCommandButton(
                key: TestIds.key(TestIds.forwardInviteNewPerson),
                label: l10n.forwardInviteNewPerson,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: onInvite,
              ),
            ),
          ),
          if (hasSelection)
            Semantics(
              identifier: TestIds.forwardClearSelection,
              child: IconButton(
                key: TestIds.key(TestIds.forwardClearSelection),
                tooltip: l10n.forwardClearSelection,
                icon: const Icon(Icons.deselect),
                onPressed: onClearSelection,
              ),
            ),
        ],
      ),
    );
  }
}
