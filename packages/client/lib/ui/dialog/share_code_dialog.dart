import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../l10n/l10n.dart';
import '../message/common_messages.dart';
import '../utils/copy_text_to_clipboard.dart';
import '../utils/ui_utils.dart';
import '../widget/qr_code.dart';

class ShareCodeDialog extends StatefulWidget {
  /// Shows the dialog and completes with whether the link may have left the
  /// screen: Copy or Share was used, the link text was selected (it may have
  /// been copied by hand), or the QR was on screen (it may have been
  /// scanned). Reported for every way of closing (Close, barrier, Esc).
  static Future<bool> show(
    BuildContext context, {
    required String header,
    // TBD: get id only, build link here
    required Uri link,
    String? caption,
  }) async {
    // Not disposed: the dialog may still rebuild during its exit animation.
    final used = ValueNotifier<bool>(false);
    await showAdaptiveDialog<void>(
      context: context,
      builder: (_) => ShareCodeDialog(
        header: header,
        link: link.toString(),
        caption: caption,
        used: used,
      ),
    );
    return used.value;
  }

  const ShareCodeDialog({
    required this.header,
    required this.link,
    this.caption,
    this.used,
    super.key,
  });

  final String header;
  final String link;

  /// Set to true once the link was copied, shared or selected, or the QR
  /// was shown.
  final ValueNotifier<bool>? used;

  /// Shown under the QR in the dialog only. Never included in [ShareParams].
  final String? caption;

  @override
  State<ShareCodeDialog> createState() => _ShareCodeDialogState();
}

class _ShareCodeDialogState extends State<ShareCodeDialog> {
  /// Desktop/tablet only: the QR is rarely the primary path there, so it
  /// waits behind a "Show QR code" toggle (#452).
  bool _qrRevealed = false;

  String get header => widget.header;

  String get link => widget.link;

  String? get caption => widget.caption;

  void _markUsed() => widget.used?.value = true;

  Future<void> _copyLink(BuildContext context, L10n l10n) async {
    _markUsed();
    final ok = await copyTextToClipboard(link);
    if (!context.mounted) return;
    // A refused write said nothing before (#349); the link stays selectable.
    showSnackBar(
      context,
      text:
          (ok
                  ? const LinkCopiedToClipboardMessage()
                  : const LinkCopyFailedMessage())
              .toL10n(l10n.localeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    // On compact (phone) the QR leads, as before; wider windows lead with the
    // link and Copy, and tuck the QR behind a toggle (#452).
    final linkFirst = context.windowClass != WindowClass.compact;
    // The QR on screen may be scanned at any moment, so it counts as used.
    if (!linkFirst || _qrRevealed) _markUsed();

    final qr = Center(child: QrCode(data: link));
    final captionText = caption != null && caption!.isNotEmpty
        ? Text(
            caption!,
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          )
        : null;
    final linkText = SelectionArea(
      // Selecting the link by hand (to copy it without the Copy button)
      // counts as used, so the hand-copied link keeps working (#605).
      onSelectionChanged: (content) {
        if (content != null && content.plainText.isNotEmpty) _markUsed();
      },
      child: Text(
        link,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
    final shareButton = Builder(
      builder: (context) => FilledButton.icon(
        icon: const Icon(Icons.share_outlined),
        label: Text(l10n.shareLink),
        onPressed: () async {
          _markUsed();
          try {
            final renderObject = context.findRenderObject();
            final sharePositionOrigin =
                renderObject is RenderBox && renderObject.hasSize
                ? renderObject.localToGlobal(Offset.zero) & renderObject.size
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
            if (context.mounted &&
                result.status == ShareResultStatus.unavailable) {
              await _copyLink(context, l10n);
            }
          } catch (e) {
            if (context.mounted) {
              await _copyLink(context, l10n);
            }
          }
        },
      ),
    );
    final copyButton = OutlinedButton.icon(
      icon: const Icon(Icons.copy_outlined),
      label: Text(l10n.copyToClipboard),
      onPressed: () => _copyLink(context, l10n),
    );

    final children = linkFirst
        ? <Widget>[
            if (captionText != null) ...[
              captionText,
              const SizedBox(height: kSpacingSmall),
            ],
            linkText,
            SizedBox(height: tt.sectionGap),
            copyButton,
            SizedBox(height: tt.rowGap),
            shareButton,
            SizedBox(height: tt.rowGap),
            if (_qrRevealed)
              qr
            else
              TextButton.icon(
                icon: const Icon(Icons.qr_code_2_outlined),
                label: Text(l10n.shareDialogShowQr),
                onPressed: () {
                  _markUsed();
                  setState(() => _qrRevealed = true);
                },
              ),
          ]
        : <Widget>[
            qr,
            if (captionText != null) ...[
              SizedBox(height: tt.rowGap),
              captionText,
            ],
            const SizedBox(height: kSpacingSmall),
            linkText,
            SizedBox(height: tt.sectionGap),
            shareButton,
            SizedBox(height: tt.rowGap),
            copyButton,
          ];

    return AlertDialog.adaptive(
      alignment: Alignment.center,
      constraints: BoxConstraints(maxWidth: tt.contentMaxWidth ?? 560),
      titlePadding: kPaddingAll,
      contentPadding: kPaddingAll,
      backgroundColor: theme.colorScheme.surfaceBright,

      // Header
      title: Text(
        header,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineMedium,
      ),

      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),

      // Buttons: share and copy are the dialog's job, so they sit with the
      // link as full-width actions; Close is the quiet dismiss below.
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // Close
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(l10n.buttonClose),
        ),
      ],
    );
  }
}
