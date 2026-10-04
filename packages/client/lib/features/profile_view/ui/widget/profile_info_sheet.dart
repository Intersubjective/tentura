import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Short explanation behind an ⓘ / 🔒 tap on the profile, so the profile
/// itself stays one compact line per fact (#134, #140).
Future<void> showProfileInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> lines,
}) => showTenturaAdaptiveSheet<void>(
  context: context,
  builder: (ctx) {
    final theme = Theme.of(ctx);
    final tt = ctx.tt;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.rowGap,
        tt.screenHPadding,
        tt.sectionGap,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          for (final line in lines) ...[
            SizedBox(height: tt.rowGap),
            Text(line, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  },
);

/// One compact profile fact: a leading icon (tappable when [onIconTap] is
/// set), a single line of text, and an optional trailing action.
class ProfileFactRow extends StatelessWidget {
  const ProfileFactRow({
    required this.icon,
    required this.text,
    this.iconTooltip,
    this.onIconTap,
    this.onTextTap,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? iconTooltip;
  final VoidCallback? onIconTap;
  final VoidCallback? onTextTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final color = theme.colorScheme.onSurfaceVariant;
    final iconWidget = Icon(icon, size: tt.iconSize, color: color);
    final label = Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: color),
    );
    return Row(
      children: [
        if (onIconTap == null)
          SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Center(child: iconWidget),
          )
        else
          IconButton(
            onPressed: onIconTap,
            tooltip: iconTooltip,
            icon: iconWidget,
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
        ?trailing,
      ],
    );
  }
}
