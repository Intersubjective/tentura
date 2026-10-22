import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/home/ui/sheet/how_tentura_works_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// First-run orientation panel — callback-only; parent owns navigation.
///
/// It shows the product, not a second copy of the onboarding pager (#523):
/// the person who vouched for the newcomer, with a way to see what they
/// need. "How Tentura works" stays one tap away in a sheet.
class HomeOrientationPanel extends StatelessWidget {
  const HomeOrientationPanel({
    required this.onCreateBeacon,
    required this.onOpenInbox,
    required this.onOpenConstellation,
    required this.onOpenTab,
    required this.onDismiss,
    this.inboxNeedsMeCount = 0,
    this.inviter,
    this.onOpenInviter,
    this.onShowHowItWorks,
    super.key,
  });

  static const inviterTitleKey = Key('HomeOrientationPanel.inviterTitle');
  static const seeInviterNeedsKey = Key('HomeOrientationPanel.seeInviterNeeds');
  static const howItWorksKey = Key('HomeOrientationPanel.howItWorks');

  final VoidCallback onCreateBeacon;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenConstellation;
  final void Function(HomeTab) onOpenTab;
  final VoidCallback onDismiss;
  final int inboxNeedsMeCount;

  /// The person who vouched for the viewer; null shows the generic welcome.
  final Profile? inviter;

  /// Opens [inviter]'s Requests.
  final VoidCallback? onOpenInviter;

  /// Defaults to the "How Tentura works" sheet.
  final VoidCallback? onShowHowItWorks;

  bool get _inboxPrimary => inboxNeedsMeCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final maxWidth = context.windowClass == WindowClass.compact ? 400.0 : 560.0;
    final inviter = this.inviter;
    final inviterName = inviter?.displayLabel(l10n.unknownPerson);
    final openInviter = inviter == null ? null : onOpenInviter;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: TenturaTechCard(
          key: TestIds.key(TestIds.orientationPanel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (inviter != null && inviterName != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TenturaAvatar.medium(profile: inviter),
                    SizedBox(width: tt.avatarTextGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.orientationInviterTitle(inviterName),
                            key: inviterTitleKey,
                            style: theme.textTheme.titleLarge,
                          ),
                          SizedBox(height: tt.tightGap),
                          Text(
                            l10n.orientationInviterIntro,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                Text(l10n.orientationTitle, style: theme.textTheme.titleLarge),
                SizedBox(height: tt.rowGap),
                Text(
                  l10n.orientationIntro,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: tt.sectionGap),
              if (_inboxPrimary) ...[
                TenturaCommandButton(
                  label: l10n.myWorkEmptyActiveInboxPrimaryCta(
                    inboxNeedsMeCount,
                  ),
                  icon: const Icon(Icons.inbox_outlined),
                  onPressed: onOpenInbox,
                ),
                SizedBox(height: tt.rowGap),
                TenturaTextAction(
                  label: l10n.myWorkEmptyActiveCreateCta,
                  onPressed: onCreateBeacon,
                ),
              ] else if (openInviter != null && inviterName != null) ...[
                TenturaCommandButton(
                  key: seeInviterNeedsKey,
                  label: l10n.orientationSeeWhatInviterNeeds(inviterName),
                  icon: const Icon(Icons.campaign_outlined),
                  onPressed: openInviter,
                ),
                SizedBox(height: tt.rowGap),
                TenturaTextAction(
                  label: l10n.myWorkEmptyActiveCreateCta,
                  onPressed: onCreateBeacon,
                ),
              ] else ...[
                TenturaCommandButton(
                  label: l10n.myWorkEmptyActiveCreateCta,
                  icon: const Icon(Icons.add),
                  onPressed: onCreateBeacon,
                ),
                SizedBox(height: tt.rowGap),
                TenturaTextAction(
                  label: l10n.constellationFindWaysToHelp,
                  onPressed: onOpenConstellation,
                ),
              ],
              SizedBox(height: tt.rowGap),
              TenturaTextAction(
                key: howItWorksKey,
                label: l10n.orientationReopen,
                onPressed:
                    onShowHowItWorks ??
                    () => unawaited(
                      showHowTenturaWorksSheet(context, onOpenTab: onOpenTab),
                    ),
              ),
              SizedBox(height: tt.rowGap),
              TenturaTextAction(
                key: TestIds.key(TestIds.orientationDismiss),
                label: l10n.orientationDismiss,
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
