import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// "Invite new person" affordance shown above the forward tab content.
///
/// Placed as the first sliver in the picker's scroll view, so it scrolls
/// away with the rest of the top sections rather than staying pinned.
class ForwardInviteBar extends StatelessWidget {
  const ForwardInviteBar({required this.onInvite, super.key});

  final VoidCallback onInvite;

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
      child: Semantics(
        identifier: TestIds.forwardInviteNewPerson,
        button: true,
        child: TextButton.icon(
          key: TestIds.key(TestIds.forwardInviteNewPerson),
          onPressed: onInvite,
          icon: Icon(
            Icons.person_add_alt_1_outlined,
            size: tt.iconSize,
          ),
          label: Text(l10n.forwardInviteNewPerson),
          style: TextButton.styleFrom(
            foregroundColor: tt.textMuted,
            textStyle: TenturaText.command(tt.textMuted),
            minimumSize: Size(0, tt.buttonHeight),
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
      ),
    );
  }
}
