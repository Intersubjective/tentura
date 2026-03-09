import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';

import '../dialog/share_code_dialog.dart';

class ShareCodeIconButton extends StatelessWidget {
  const ShareCodeIconButton({
    required this.header,
    required this.link,
    super.key,
  });

  ShareCodeIconButton.id(
    String id, {
    Key? key,
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
       );

  final String header;
  final Uri link;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.qr_code),
    onPressed: () => ShareCodeDialog.show(
      context,
      link: link,
      header: header,
    ),
  );
}
