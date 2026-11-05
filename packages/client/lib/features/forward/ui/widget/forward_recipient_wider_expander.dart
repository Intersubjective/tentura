import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Collapsed «Wider network» overflow control in the forward recipient picker
/// (#440 mn5y.4).
class ForwardRecipientWiderExpander extends StatelessWidget {
  const ForwardRecipientWiderExpander({
    required this.hiddenCount,
    required this.onExpand,
    super.key,
  });

  final int hiddenCount;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final title = l10n.forwardWiderNetworkMorePeople(hiddenCount);
    final hint = l10n.forwardWiderNetworkExpanderHint;

    return Semantics(
      button: true,
      expanded: false,
      label: '$title. $hint',
      child: InkWell(
        onTap: onExpand,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.rowGap,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.expand_more,
                size: tt.iconSize,
                color: scheme.primary,
              ),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TenturaText.titleSmall(scheme.onSurface),
                    ),
                    SizedBox(height: tt.tightGap),
                    Text(
                      hint,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
