import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../l10n/l10n.dart';
import '../message/common_messages.dart';
import '../utils/copy_text_to_clipboard.dart';
import '../utils/ui_utils.dart';
import '../widget/qr_code.dart';

class ShareCodeDialog extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required String header,
    // TBD: get id only, build link here
    required Uri link,
    String? caption,
  }) => showAdaptiveDialog(
    context: context,
    builder: (_) => ShareCodeDialog(
      header: header,
      link: link.toString(),
      caption: caption,
    ),
  );

  const ShareCodeDialog({
    required this.header,
    required this.link,
    this.caption,
    super.key,
  });

  final String header;
  final String link;

  /// Shown under the QR in the dialog only. Never included in [ShareParams].
  final String? caption;

  Future<void> _copyLink(BuildContext context, L10n l10n) async {
    final ok = await copyTextToClipboard(link);
    if (ok && context.mounted) {
      showSnackBar(
        context,
        text: const LinkCopiedToClipboardMessage().toL10n(
          l10n.localeName,
        ),
      );
    }
  }

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
        header,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium,
      ),

      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: QrCode(data: link)),
            if (caption != null && caption!.isNotEmpty) ...[
              SizedBox(height: tt.rowGap),
              Text(
                caption!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: kSpacingSmall),
            SelectionArea(
              child: Text(
                link,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),

      // Buttons
      actions: [
        // Copy to Clipboard
        TextButton(
          child: Text(l10n.copyToClipboard),
          onPressed: () => _copyLink(context, l10n),
        ),

        // Share Link
        Builder(
          builder: (context) => TextButton(
            child: Text(l10n.shareLink),
            onPressed: () async {
              try {
                final renderObject = context.findRenderObject();
                final sharePositionOrigin =
                    renderObject is RenderBox && renderObject.hasSize
                    ? renderObject.localToGlobal(Offset.zero) &
                          renderObject.size
                    : null;
                final result = await SharePlus.instance.share(
                  ShareParams(
                    subject: header,
                    title: l10n.shareLink,
                    uri: Uri.parse(link),
                    mailToFallbackEnabled: false,
                    // iPad popover anchor; optional on other platforms.
                    sharePositionOrigin: sharePositionOrigin,
                  ),
                );
                if (context.mounted) {
                  if (result.status == ShareResultStatus.unavailable) {
                    await _copyLink(context, l10n);
                  } else if (result.status == ShareResultStatus.success) {
                    showSnackBar(
                      context,
                      text: result.toString(),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  await _copyLink(context, l10n);
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
