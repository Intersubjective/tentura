import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Pre-send disclosure: shared chat audience and history visibility.
class RoomVisibilityCallout extends StatelessWidget {
  const RoomVisibilityCallout({
    required this.onDismiss,
    super.key,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      label:
          '${l10n.beaconRoomVisibilityCalloutTitle}. '
          '${l10n.beaconRoomVisibilityCalloutBody}',
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.tightGap,
          tt.screenHPadding,
          tt.rowGap,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            border: Border.all(color: tt.borderSubtle),
          ),
          child: Padding(
            padding: tt.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.groups_outlined,
                      size: tt.iconSize,
                      color: scheme.primary,
                    ),
                    SizedBox(width: tt.iconTextGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.beaconRoomVisibilityCalloutTitle,
                            style: TenturaText.titleSmall(scheme.onSurface),
                          ),
                          SizedBox(height: tt.tightGap),
                          Text(
                            l10n.beaconRoomVisibilityCalloutBody,
                            style: TenturaText.bodySmall(tt.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: tt.rowGap),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onDismiss,
                    child: Text(l10n.beaconRoomVisibilityCalloutDismiss),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
