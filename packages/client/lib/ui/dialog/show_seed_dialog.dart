import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/qr_code.dart';

class ShowSeedDialog extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required String seed,
  }) => showAdaptiveDialog(
    context: context,
    builder: (_) => ShowSeedDialog(seed: seed),
  );

  const ShowSeedDialog({
    required this.seed,
    super.key,
  });

  final String seed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return AlertDialog.adaptive(
      alignment: Alignment.center,
      actionsAlignment: MainAxisAlignment.spaceBetween,
      constraints: BoxConstraints(maxWidth: tt.contentMaxWidth ?? 560),
      titlePadding: kPaddingAll,
      contentPadding: kPaddingAll,
      backgroundColor: theme.colorScheme.surfaceBright,

      // Header
      title: Text(
        seed,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium,
      ),

      content: Center(child: QrCode(data: seed)),

      // Buttons
      actions: [
        TextButton(
          child: Text(l10n.copyToClipboard),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: seed));
            if (context.mounted) {
              showSnackBar(context, text: l10n.seedCopied);
            }
          },
        ),
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonClose),
        ),
      ],
    );
  }
}
