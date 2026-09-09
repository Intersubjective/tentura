import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/contact_badge_legend.dart';

Future<void> showTrustInfoSheet(BuildContext context) =>
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.trustInfoTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              SizedBox(height: tt.rowGap),
              Text(
                l10n.trustInfoBody,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              SizedBox(height: tt.sectionGap),
              const ContactBadgeLegend(showTextLabelNote: true),
            ],
          ),
        );
      },
    );
