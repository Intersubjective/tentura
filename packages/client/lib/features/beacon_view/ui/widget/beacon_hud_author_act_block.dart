import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_hud_action_button.dart';

/// Author HUD primary action: verb button plus outcome effect disclosure.
class BeaconHudAuthorActBlock extends StatelessWidget {
  const BeaconHudAuthorActBlock({
    required this.spec,
    required this.onPressed,
    super.key,
  });

  final BeaconHudAuthorActSpec spec;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final presentation = spec.effectPresentation;
    final actionButton = BeaconHudActionButton(
      key: TestIds.key(TestIds.beaconHudAuthorAction(spec.action.name)),
      icon: spec.icon,
      label: spec.label,
      onPressed: onPressed,
      filled: spec.filled,
      minimumSize: const Size(48, 48),
    );
    final buttonChild = switch (presentation) {
      BeaconHudAuthorActEffectPresentation.tooltip => Tooltip(
          message: spec.effectLine,
          child: actionButton,
        ),
      BeaconHudAuthorActEffectPresentation.mutedSubtitle ||
      BeaconHudAuthorActEffectPresentation.hiddenKeepSemantics =>
        actionButton,
    };
    return Semantics(
      identifier: TestIds.beaconHudAuthorAction(spec.action.name),
      button: true,
      label: spec.semanticsLabel,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: buttonChild,
          ),
          if (presentation ==
              BeaconHudAuthorActEffectPresentation.mutedSubtitle) ...[
            SizedBox(height: tt.tightGap),
            Text(
              spec.effectLine,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
