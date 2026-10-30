import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import 'constellation_anchor_controls.dart';
import 'constellation_request_status_marker.dart';

/// An inaccessible pin explains its state and offers only Unpin.
class ConstellationPinPlaceholderSheet extends StatelessWidget {
  const ConstellationPinPlaceholderSheet({
    required this.target,
    required this.pinState,
    this.onClose,
    super.key,
  });

  final ConstellationAnchorTarget target;
  final String? pinState;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Material(
      key: const Key('constellation.pin_placeholder'),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(tt.cardRadius),
      child: Padding(
        padding: tt.cardPadding,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: tt.textMuted),
                  SizedBox(width: tt.iconTextGap),
                  Expanded(
                    child: Text(
                      constellationPinStateLabel(l10n, pinState),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      tooltip: l10n.buttonClose,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              SizedBox(height: tt.rowGap),
              Text(
                constellationPinStateExplanation(l10n, pinState),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              SizedBox(height: tt.sectionGap),
              ConstellationAnchorTargetButton(target: target),
            ],
          ),
        ),
      ),
    );
  }
}
