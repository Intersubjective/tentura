import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/copy_text_to_clipboard.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/qr_code.dart';

/// Shows the recovery seed with what it is and a warning above it.
///
/// Closing needs the "I saved it" tick first; the backdrop and back gesture
/// do not skip that step. The dialog is also reopened later (Settings, the
/// account tile), so it does not claim the seed is shown only once.
class ShowSeedDialog extends StatefulWidget {
  static Future<void> show(
    BuildContext context, {
    required String seed,
  }) => showAdaptiveDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ShowSeedDialog(seed: seed),
  );

  const ShowSeedDialog({
    required this.seed,
    super.key,
  });

  final String seed;

  @override
  State<ShowSeedDialog> createState() => _ShowSeedDialogState();
}

class _ShowSeedDialogState extends State<ShowSeedDialog> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final seed = widget.seed;
    return PopScope(
      canPop: _saved,
      // Plain material dialog: the content is material (checkbox tile), and
      // AlertDialog.adaptive is a subclass, not an AlertDialog, at runtime.
      child: AlertDialog(
        scrollable: true,
        alignment: Alignment.center,
        actionsAlignment: MainAxisAlignment.spaceBetween,
        constraints: BoxConstraints(maxWidth: tt.contentMaxWidth ?? 560),
        titlePadding: kPaddingAll,
        contentPadding: kPaddingAll,
        backgroundColor: theme.colorScheme.surfaceBright,

        // Header: what this is, not the secret itself
        title: Text(
          l10n.seedBackupTitle,
          textAlign: TextAlign.center,
        ),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.seedDialogWarning,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: kSpacingMedium),
            Text(
              seed,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: kSpacingMedium),
            Center(child: QrCode(data: seed)),
            const SizedBox(height: kSpacingSmall),
            CheckboxListTile(
              value: _saved,
              onChanged: (value) => setState(() => _saved = value ?? false),
              title: Text(l10n.seedBackupConfirm),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),

        // Buttons
        actions: [
          TextButton(
            child: Text(l10n.copyToClipboard),
            onPressed: () async {
              final ok = await copyTextToClipboard(seed);
              if (ok && context.mounted) {
                showSnackBar(context, text: l10n.seedCopied);
              }
            },
          ),
          TextButton(
            onPressed: _saved ? Navigator.of(context).pop : null,
            child: Text(l10n.buttonClose),
          ),
        ],
      ),
    );
  }
}
