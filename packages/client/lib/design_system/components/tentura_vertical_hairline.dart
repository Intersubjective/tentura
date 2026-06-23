import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

/// 1 px vertical separator using token border color.
class TenturaVerticalHairline extends StatelessWidget {
  const TenturaVerticalHairline({
    super.key,
    this.subtle = true,
  });

  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return VerticalDivider(
      width: 1,
      thickness: 1,
      color: subtle ? tt.borderSubtle : tt.border,
    );
  }
}
