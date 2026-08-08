import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// People top-bar actions: Graph, Create invitation, and More (QR, Blocked).
class FriendsAppBarActions extends StatelessWidget {
  const FriendsAppBarActions({
    required this.onGraph,
    required this.onCreateInvitation,
    required this.onScanInvitationQr,
    required this.onBlockedPeople,
    super.key,
  });

  final VoidCallback onGraph;
  final VoidCallback onCreateInvitation;
  final VoidCallback onScanInvitationQr;
  final VoidCallback onBlockedPeople;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final touchTarget = BoxConstraints(
      minWidth: tt.buttonHeight,
      minHeight: tt.buttonHeight,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: TestIds.key(TestIds.friendsGraph),
          tooltip: l10n.friendsPeopleGraph,
          onPressed: onGraph,
          icon: const Icon(TenturaIcons.graph),
          padding: EdgeInsets.zero,
          constraints: touchTarget,
        ),
        IconButton(
          key: TestIds.key(TestIds.friendsCreateInvitation),
          tooltip: l10n.friendsCreateInvitation,
          onPressed: onCreateInvitation,
          icon: const Icon(Icons.person_add_alt_1),
          padding: EdgeInsets.zero,
          constraints: touchTarget,
        ),
        PopupMenuButton<String>(
          key: TestIds.key(TestIds.friendsMore),
          icon: const Icon(Icons.more_vert),
          tooltip: l10n.friendsPeopleMore,
          padding: EdgeInsets.zero,
          constraints: touchTarget,
          onSelected: (value) {
            switch (value) {
              case 'scan':
                onScanInvitationQr();
              case 'blocked':
                onBlockedPeople();
            }
          },
          itemBuilder: (menuContext) => [
            PopupMenuItem<String>(
              value: 'scan',
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: tt.iconSize,
                    color: Theme.of(menuContext).colorScheme.onSurface,
                  ),
                  SizedBox(width: tt.rowGap),
                  Text(l10n.friendsScanInviteCode),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'blocked',
              child: Row(
                children: [
                  Icon(
                    Icons.block_outlined,
                    size: tt.iconSize,
                    color: Theme.of(menuContext).colorScheme.onSurface,
                  ),
                  SizedBox(width: tt.rowGap),
                  Text(l10n.friendsBlockedPeople),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
