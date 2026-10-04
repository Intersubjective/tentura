import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';

import '../dialog/share_code_dialog.dart';
import '../l10n/l10n.dart';

class ShareCodeIconButton extends StatelessWidget {
  const ShareCodeIconButton({
    required this.header,
    required this.link,
    this.icon = Icons.qr_code,
    super.key,
  });

  /// [displayName] titles the dialog; the raw id was shown before, which
  /// meant nothing to the person scanning (UI review).
  ShareCodeIconButton.id(
    String id, {
    String? displayName,
    Key? key,
    IconData icon = Icons.qr_code,
  }) : this(
         key: key,
         header: (displayName == null || displayName.trim().isEmpty)
             ? id
             : displayName.trim(),
         // The id is in the path; the old `?id=` duplicate only padded the
         // URL printed under the QR. Pasted / scanned links resolve through
         // extractEntityIdFromText, which still accepts legacy `?id=` links.
         link: Uri.parse(kServerName).replace(path: '$kPathProfileView/$id'),
         icon: icon,
       );

  final String header;
  final Uri link;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    tooltip: L10n.of(context)?.tooltipShareCode,
    onPressed: () => ShareCodeDialog.show(
      context,
      link: link,
      header: header,
    ),
  );
}
