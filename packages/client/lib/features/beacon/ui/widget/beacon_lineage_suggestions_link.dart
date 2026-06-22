import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../util/beacon_lineage_overflow_actions.dart';

/// Opens the lineage forward-suggestions preview sheet for [beaconId].
class BeaconLineageSuggestionsLink extends StatelessWidget {
  const BeaconLineageSuggestionsLink({
    required this.beaconId,
    super.key,
  });

  final String beaconId;

  @override
  Widget build(BuildContext context) {
    if (beaconId.isEmpty) return const SizedBox.shrink();
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return Semantics(
      button: true,
      label: l10n.beaconLineageSuggestionsLinkSemantics,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => runBeaconLineageSuggestionsPreview(
            context,
            beaconId: beaconId,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap * 0.5,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  SizedBox(width: tt.rowGap * 0.75),
                  Expanded(
                    child: Text(
                      l10n.beaconLineageSuggestionsAction,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
