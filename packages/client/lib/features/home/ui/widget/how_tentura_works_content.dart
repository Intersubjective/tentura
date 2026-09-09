import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Shared orientation body: title, intro, how-it-works steps, and nav map.
///
/// Callback-only — parent owns tab switching via [onOpenTab].
class HowTenturaWorksContent extends StatelessWidget {
  const HowTenturaWorksContent({
    required this.title,
    required this.intro,
    this.onOpenTab,
    super.key,
  });

  final String title;
  final String intro;
  final void Function(HomeTab)? onOpenTab;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge,
        ),
        SizedBox(height: tt.rowGap),
        Text(
          intro,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.orientationHowTitle,
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        _OrientStep(number: 1, text: l10n.orientationHowStep1),
        SizedBox(height: tt.rowGap),
        _OrientStep(number: 2, text: l10n.orientationHowStep2),
        SizedBox(height: tt.rowGap),
        _OrientStep(number: 3, text: l10n.orientationHowStep3),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.orientationWhereTitle,
          style: theme.textTheme.titleSmall,
        ),
        SizedBox(height: tt.rowGap),
        _OrientNavRow(
          icon: Icons.work_outline,
          label: l10n.myWork,
          description: l10n.orientationWhereWork,
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.myWork,
            l10n.orientationWhereWork,
          ),
          minHeight: math.max(tt.buttonHeight, 48),
          onTap: onOpenTab == null ? null : () => onOpenTab!(HomeTab.work),
        ),
        _OrientNavRow(
          icon: Icons.inbox_outlined,
          label: l10n.inbox,
          description: l10n.orientationWhereInbox,
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.inbox,
            l10n.orientationWhereInbox,
          ),
          minHeight: math.max(tt.buttonHeight, 48),
          onTap: onOpenTab == null ? null : () => onOpenTab!(HomeTab.inbox),
        ),
        _OrientNavRow(
          icon: TenturaIcons.graph,
          label: l10n.constellationNavLabel,
          description: l10n.orientationWhereField,
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.constellationNavLabel,
            l10n.orientationWhereField,
          ),
          minHeight: math.max(tt.buttonHeight, 48),
          onTap:
              onOpenTab == null ? null : () => onOpenTab!(HomeTab.constellation),
        ),
        _OrientNavRow(
          icon: Icons.people_outline,
          label: l10n.network,
          description: l10n.orientationWhereNetwork,
          semanticsLabel: l10n.orientationWhereSemantics(
            l10n.network,
            l10n.orientationWhereNetwork,
          ),
          minHeight: math.max(tt.buttonHeight, 48),
          onTap: onOpenTab == null ? null : () => onOpenTab!(HomeTab.network),
        ),
      ],
    );
  }
}

class _OrientStep extends StatelessWidget {
  const _OrientStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: tt.iconSize,
          child: Text(
            '$number',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _OrientNavRow extends StatelessWidget {
  const _OrientNavRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.semanticsLabel,
    required this.minHeight,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final String semanticsLabel;
  final double minHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;

    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: tt.tightGap),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: tt.iconSize,
                color: scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(width: tt.iconTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: tt.iconSize,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    final content = ExcludeSemantics(
      child: onTap == null
          ? row
          : InkWell(
              onTap: onTap,
              child: row,
            ),
    );

    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      container: true,
      child: content,
    );
  }
}
