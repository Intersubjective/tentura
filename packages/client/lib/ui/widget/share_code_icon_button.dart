import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';

import '../dialog/share_code_dialog.dart';

class ShareCodeIconButton extends StatelessWidget {
  const ShareCodeIconButton({
    required this.header,
    required this.link,
    this.icon = Icons.qr_code,
    super.key,
  });

  ShareCodeIconButton.id(
    String id, {
    Key? key,
    IconData icon = Icons.qr_code,
  }) : this(
         key: key,
         header: id,
         link:
             Uri.parse(
               kServerName,
             ).replace(
               queryParameters: {'id': id},
               path: kPathAppLinkView,
             ),
         icon: icon,
       );

  final String header;
  final Uri link;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    onPressed: () => ShareCodeDialog.show(
      context,
      link: link,
      header: header,
    ),
  );
}
