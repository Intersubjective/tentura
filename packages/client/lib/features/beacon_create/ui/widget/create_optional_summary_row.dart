import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Compact tappable row that opens an optional-field editor (sheet/dialog).
class CreateOptionalSummaryRow extends StatelessWidget {
  const CreateOptionalSummaryRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.keyId,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Key? keyId;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: keyId,
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: tt.tightGap * 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tt.tightGap / 2),
                    Text(
                      subtitle,
                      style: TenturaText.bodySmall(
                        theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
