import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Now-tab notice for a viewer whose help offer the author declined.
///
/// Without it the decline was silent: the offer vanished and "Offer help"
/// came back as if nothing had happened (UI review #216).
class DeclinedOfferNotice extends StatelessWidget {
  const DeclinedOfferNotice({
    required this.reason,
    required this.canOfferAgain,
    super.key,
  });

  /// The author's decline note; hidden when empty.
  final String? reason;

  /// Shows the "you can offer again" hint when Offer help is available.
  final bool canOfferAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final note = reason?.trim() ?? '';
    return TenturaTechCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.do_not_disturb_on_outlined,
            size: tt.iconSize,
            color: tenturaToneColor(tt, TenturaTone.danger),
          ),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.helpOfferDeclinedNoticeTitle,
                  style: TenturaText.titleSmall(scheme.onSurface),
                ),
                if (note.isNotEmpty) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    l10n.helpOfferDeclinedNoticeReasonLabel,
                    style: TenturaText.status(scheme.onSurfaceVariant),
                  ),
                  Text(note, style: TenturaText.body(scheme.onSurface)),
                ],
                if (canOfferAgain) ...[
                  SizedBox(height: tt.tightGap),
                  Text(
                    l10n.helpOfferDeclinedNoticeHint,
                    style: TenturaText.bodySmall(scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
