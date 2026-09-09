import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../widget/how_tentura_works_content.dart';

Future<void> showHowTenturaWorksSheet(
  BuildContext context, {
  void Function(HomeTab)? onOpenTab,
}) =>
    showTenturaAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) {
        final l10n = L10n.of(ctx)!;
        final tt = ctx.tt;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            tt.rowGap,
            tt.screenHPadding,
            tt.sectionGap,
          ),
          child: HowTenturaWorksContent(
            title: l10n.orientationReopen,
            intro: l10n.orientationIntroReopen,
            onOpenTab: onOpenTab == null
                ? null
                : (tab) {
                    Navigator.of(ctx).pop();
                    onOpenTab(tab);
                  },
          ),
        );
      },
    );
