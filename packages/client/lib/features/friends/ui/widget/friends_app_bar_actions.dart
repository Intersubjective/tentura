import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/trust_info_sheet.dart';

/// People top-bar actions: Graph, Create invitation, Scan invite code, and
/// More (Blocked; trust info on compact bars).
class FriendsAppBarActions extends StatelessWidget {
  const FriendsAppBarActions({
    required this.onGraph,
    required this.onCreateInvitation,
    required this.onScanInvitationQr,
    required this.onBlockedPeople,
    this.compact = false,
    super.key,
  });

  /// Compact bars cannot fit every icon: the trust explainer moves into ⋮.
  final bool compact;

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
        if (!compact)
          IconButton(
            key: TestIds.key(TestIds.friendsTrustInfo),
            tooltip: l10n.trustInfoTitle,
            onPressed: () => showTrustInfoSheet(context),
            icon: const Icon(Icons.info_outline),
            padding: EdgeInsets.zero,
            constraints: touchTarget,
          ),
        // Scanning an invite code is how people join each other: a
        // first-class action, not a menu entry.
        IconButton(
          key: const Key('friends.app_bar.scan_invite'),
          tooltip: l10n.friendsScanInviteCode,
          onPressed: onScanInvitationQr,
          icon: const Icon(Icons.qr_code_scanner),
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
              case 'blocked':
                onBlockedPeople();
              case 'trust':
                showTrustInfoSheet(context);
            }
          },
          itemBuilder: (menuContext) => [
            if (compact)
              PopupMenuItem<String>(
                key: TestIds.key(TestIds.friendsTrustInfo),
                value: 'trust',
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: tt.iconSize,
                      color: Theme.of(menuContext).colorScheme.onSurface,
                    ),
                    SizedBox(width: tt.rowGap),
                    Text(l10n.trustInfoTitle),
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
