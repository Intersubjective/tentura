import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Your own trust vote toward a person as one line with a toggle (#140).
/// Replaces the "Trust this user" buttons on the profile and in person
/// mini-profiles. Callers confirm withdrawal (the toggle only reports intent).
class TrustToggleLine extends StatelessWidget {
  const TrustToggleLine({
    required this.trusts,
    required this.onChanged,
    this.onTextTap,
    this.switchKey,
    super.key,
  });

  final bool trusts;

  /// `null` disables the toggle (e.g. while a change is in flight).
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTextTap;
  final Key? switchKey;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final color = theme.colorScheme.onSurfaceVariant;
    final label = Text(
      trusts ? l10n.trustSentenceOneWayOut : l10n.profileTrustNotYet,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: color),
    );
    return Row(
      children: [
        SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Center(
            child: Icon(
              trusts ? Icons.handshake_outlined : Icons.person_outline,
              size: tt.iconSize,
              color: color,
            ),
          ),
        ),
        Expanded(
          child: onTextTap == null
              ? label
              : InkWell(
                  onTap: onTextTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: kMinInteractiveDimension,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: label,
                    ),
                  ),
                ),
        ),
        Tooltip(
          message: trusts ? l10n.removeFromMyField : l10n.trustThisUser,
          child: Switch.adaptive(
            key: switchKey,
            value: trusts,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
