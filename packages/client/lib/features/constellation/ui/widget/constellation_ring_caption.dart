import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// «{n} steps»: names the trust ring nearest to a node being dragged.
class ConstellationRingCaption extends StatelessWidget {
  const ConstellationRingCaption({required this.steps, super.key});

  final int steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: scheme.primaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TenturaSpacing.row,
          vertical: TenturaSpacing.tight,
        ),
        child: Text(
          L10n.of(context)!.constellationRingSteps(steps),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
