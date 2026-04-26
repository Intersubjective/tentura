import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Uppercase type / offer line (`TenturaText.typeLabel`, Inter + letter spacing).
class TenturaTypeLabel extends StatelessWidget {
  const TenturaTypeLabel(
    this.text, {
    super.key,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TenturaText.typeLabel(context.tt.textMuted),
    );
  }
}
