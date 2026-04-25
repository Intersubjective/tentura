import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// 1 px separator using token border or subtle border.
class TenturaHairlineDivider extends StatelessWidget {
  const TenturaHairlineDivider({
    super.key,
    this.subtle = true,
  });

  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Divider(
      height: 1,
      thickness: 1,
      color: subtle ? tt.borderSubtle : tt.border,
    );
  }
}
