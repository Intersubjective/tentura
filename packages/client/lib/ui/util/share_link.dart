import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../message/common_messages.dart';
import 'copy_text_to_clipboard.dart';
import 'ui_utils.dart';

Future<void> copyShareLink(
  BuildContext context, {
  required String link,
  String? text,
}) async {
  final ok = await copyTextToClipboard(text ?? link);
  if (!context.mounted) return;
  showSnackBar(
    context,
    text:
        (ok
                ? const LinkCopiedToClipboardMessage()
                : const LinkCopyFailedMessage())
            .toL10n(L10n.of(context)!.localeName),
  );
}

Future<void> shareLink(
  BuildContext context, {
  required String link,
  String? subject,
  String? text,
}) async {
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        subject: subject,
        title: L10n.of(context)!.shareLink,
        uri: text == null ? Uri.parse(link) : null,
        text: text,
        mailToFallbackEnabled: false,
        sharePositionOrigin: origin,
      ),
    );
    if (result.status != ShareResultStatus.unavailable) return;
  } on Exception {
    // A platform that cannot open its share sheet can still copy the content.
  }
  if (context.mounted) {
    await copyShareLink(context, link: link, text: text);
  }
}
