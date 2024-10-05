import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'package:tentura/ui/utils/ui_utils.dart';

import '../theme.dart';

class ShareCodeDialog extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required String header,
    required Uri link,
  }) =>
      showDialog(
        context: context,
        useRootNavigator: false,
        builder: (context) => ShareCodeDialog(
          header: header,
          link: link.toString(),
        ),
      );

  final String header;
  final String link;

  const ShareCodeDialog({
    required this.header,
    required this.link,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        style: theme.textTheme.headlineLarge,
      ),

      // QRCode
      content: PrettyQrView.data(
        key: ValueKey(header),
        data: header,
        decoration: PrettyQrDecoration(
          shape: PrettyQrSmoothSymbol(
            // We can`t read inverted QR
            color: themeLight.colorScheme.onSurface,
          ),
        ),
      ),

      // Buttons
      actions: [
        Builder(
          builder: (context) => TextButton(
            child: const Text('Share Link'),
            onPressed: () {
              final box = context.findRenderObject()! as RenderBox;
              Share.share(
                link,
                sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
              );
            },
          ),
        ),
        TextButton(
          onPressed: context.maybePop,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
