import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../message/common_messages.dart';
import '../utils/ui_utils.dart';
import '../widget/qr_code.dart';

class ShareCodeDialog extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required String header,
    // TBD: get id only, build link here
    required Uri link,
  }) => showAdaptiveDialog(
    context: context,
    builder: (_) => ShareCodeDialog(
      header: header,
      link: link.toString(),
    ),
  );

  const ShareCodeDialog({
    required this.header,
    required this.link,
    super.key,
  });

  final String header;
  final String link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    return AlertDialog.adaptive(
      alignment: Alignment.center,
      actionsAlignment: MainAxisAlignment.spaceBetween,
      titlePadding: kPaddingAll,
      contentPadding: kPaddingAll,
      backgroundColor: theme.colorScheme.surfaceBright,

      // Header
      title: Text(
        header,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium,
      ),

      // QRCode
      content: QrCode(data: link),

      // Buttons
      actions: [
        // Copy to Clipboard
        TextButton(
          child: Text(l10n.copyToClipboard),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              showSnackBar(
                context,
                text: const LinkCopiedToClipboardMessage().toL10n(
                  l10n.localeName,
                ),
              );
            }
          },
        ),

        // Share Link
        Builder(
          builder: (context) => TextButton(
            child: Text(l10n.shareLink),
            onPressed: () async {
              try {
                final box = context.findRenderObject()! as RenderBox;
                final result = await SharePlus.instance.share(
                  ShareParams(
                    subject: header,
                    title: l10n.shareLink,
                    uri: Uri.parse(link),
                    mailToFallbackEnabled: false,
                    // This needed for iPad
                    sharePositionOrigin:
                        box.localToGlobal(Offset.zero) & box.size,
                  ),
                );
                if (context.mounted) {
                  showSnackBar(
                    context,
                    text: result.toString(),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(
                    context,
                    text: e.toString(),
                    isError: true,
                  );
                }
              }
            },
          ),
        ),

        // Close
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonClose),
        ),
      ],
    );
  }
}
