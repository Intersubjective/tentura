import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/components/tentura_command_button.dart';
import 'package:tentura/design_system/components/tentura_text_action.dart';
import 'package:tentura/design_system/components/tentura_tech_card.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/design_system/tentura_window_class.dart';
import 'package:tentura/features/home/ui/widget/how_tentura_works_content.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// First-run orientation panel — callback-only; parent owns navigation.
class HomeOrientationPanel extends StatelessWidget {
  const HomeOrientationPanel({
    required this.onCreateBeacon,
    required this.onOpenInbox,
    required this.onOpenConstellation,
    required this.onOpenTab,
    required this.onDismiss,
    this.inboxNeedsMeCount = 0,
    super.key,
  });

  final VoidCallback onCreateBeacon;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenConstellation;
  final void Function(HomeTab) onOpenTab;
  final VoidCallback onDismiss;
  final int inboxNeedsMeCount;

  bool get _inboxPrimary => inboxNeedsMeCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final maxWidth = context.windowClass == WindowClass.compact ? 400.0 : 560.0;

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
              HowTenturaWorksContent(
                title: l10n.orientationTitle,
                intro: l10n.orientationIntro,
                onOpenTab: onOpenTab,
              ),
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
