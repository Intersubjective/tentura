import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// Footer for sheets and dialogs that end in a decision: a quiet Cancel text
/// button beside an expanded primary button, on one row.
///
/// Replaces the stacked "centred Cancel over a full-width primary" footer that
/// read as two separate rows and put Cancel where the eye lands first.
class TenturaSheetActions extends StatelessWidget {
  const TenturaSheetActions({
    required this.primaryLabel,
    required this.onPrimary,
    this.cancelLabel,
    this.onCancel,
    this.primaryKey,
    this.destructive = false,
    super.key,
  });

  final String primaryLabel;

  /// `null` disables the primary button (e.g. a required field is empty).
  final VoidCallback? onPrimary;

  final String? cancelLabel;
  final VoidCallback? onCancel;
  final Key? primaryKey;

  /// Paints the primary button in the error role (decline, delete, remove).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final cancel = cancelLabel;
    return Row(
      children: [
        if (cancel != null) ...[
          TextButton(onPressed: onCancel, child: Text(cancel)),
          SizedBox(width: tt.rowGap),
        ],
        Expanded(
          child: FilledButton(
            key: primaryKey,
            onPressed: onPrimary,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(primaryLabel),
          ),
        ),
      ],
    );
  }
}
