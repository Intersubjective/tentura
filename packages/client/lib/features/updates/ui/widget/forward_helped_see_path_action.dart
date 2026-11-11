import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/forward_helped_receipt_copy.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// «See the path ›» for a forward-helped Updates row (#774).
class ForwardHelpedSeePathAction extends StatelessWidget {
  const ForwardHelpedSeePathAction({
    required this.receipt,
    this.requestClosed = false,
    super.key,
  });

  final AttentionReceipt receipt;
  final bool requestClosed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final content = forwardHelpedFromPresentationPayload(
      receipt.presentationPayloadJson,
    );
    final beaconId = receipt.beaconId?.trim();
    final helperId = content?.helperId;
    if (content == null ||
        beaconId == null ||
        beaconId.isEmpty ||
        helperId == null ||
        helperId.isEmpty) {
      return const SizedBox.shrink();
    }
    return TenturaTextAction(
      label: l10n.updatesForwardHelpedSeePath,
      flushStart: true,
      onPressed: () {
        final screen = context.read<ScreenCubit>();
        if (requestClosed || content.done) {
          // Closed Requests are absent from the Field snapshot. Their detail
          // already shows the canonical "Help came through" path.
          screen.showBeacon(beaconId, entry: kBeaconEntryInbox);
        } else {
          screen.showConstellationForwardTreeFor(
            beaconId: beaconId,
            helpOffererId: helperId,
          );
        }
      },
    );
  }
}
