import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/widget/forward_recipient_picker.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Recipients tab on beacon create — routing banner + embedded forward picker.
class BeaconRecipientsTab extends StatelessWidget {
  const BeaconRecipientsTab({
    required this.beaconId,
    super.key,
  });

  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(tt.cardPadding.top),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.send_outlined,
                  size: tt.iconSize,
                  color: scheme.onSurfaceVariant,
                ),
                SizedBox(width: tt.tightGap * 2),
                Expanded(
                  child: Text(
                    l10n.beaconRoutingBanner,
                    style: TenturaText.body(scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: tt.rowGap),
        Expanded(
          child: ForwardRecipientPicker(
            key: ValueKey(beaconId),
            beaconId: beaconId,
            embedded: true,
          ),
        ),
      ],
    );
  }
}
