import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// One row inside the create-form Details card.
class CreateDetailsRow extends StatelessWidget {
  const CreateDetailsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
    this.trailing,
    this.keyId,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool filled;
  final Widget? trailing;
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
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tt.buttonHeight),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tt.cardPadding.top),
            child: Row(
              children: [
                Icon(icon, size: tt.iconSize, color: tt.textMuted),
                SizedBox(width: tt.avatarTextGap),
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
                          filled ? tt.text : tt.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
                Icon(
                  Icons.chevron_right_rounded,
                  color: tt.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
