import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart';
import 'package:tentura/features/forward/ui/message/forward_messages.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Confirmation after publish + forward from beacon create.
class BeaconSendConfirmationDialog extends StatelessWidget {
  const BeaconSendConfirmationDialog({
    required this.outcome,
    super.key,
  });

  final ForwardDeliveryOutcome outcome;

  static Future<void> show(
    BuildContext context, {
    required ForwardDeliveryOutcome outcome,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BeaconSendConfirmationDialog(outcome: outcome),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final failed = outcome.failed;
    final locale = Localizations.localeOf(context).languageCode;
    final deliveredOf = ForwardDeliveredOfMessage(
      deliveredCount: outcome.deliveredCount,
      requestedCount: outcome.requestedCount,
    );

    return AlertDialog(
      title: Text(l10n.beaconSendConfirmationTitle),
      content: Text(
        failed
            ? l10n.beaconSendConfirmationFailed
            : deliveredOf.toL10n(locale),
        style: TenturaText.body(tt.text),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.buttonOk),
        ),
      ],
    );
  }
}
