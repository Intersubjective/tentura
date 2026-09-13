import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Section title row: uppercase type label, optional `· N` count, optional helper.
class TenturaSectionHeader extends StatelessWidget {
  const TenturaSectionHeader({
    required this.label,
    super.key,
    this.count,
    this.helperText,
    this.semanticsIdentifier,
  });

  final String label;
  final int? count;
  final String? helperText;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final labelText = count == null
        ? label.toUpperCase()
        : '${label.toUpperCase()} · $count';

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          labelText,
          style: TenturaText.typeLabel(tt.textFaint),
        ),
        if (helperText != null) ...[
          SizedBox(height: tt.tightGap),
          Text(
            helperText!,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ],
      ],
    );

    final identifier = semanticsIdentifier;
    return Padding(
      padding: EdgeInsets.only(top: tt.sectionGap, bottom: tt.tightGap),
      child: Semantics(
        header: true,
        identifier: identifier,
        child: header,
      ),
    );
  }
}
