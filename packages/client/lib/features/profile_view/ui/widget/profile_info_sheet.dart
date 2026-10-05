import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Short explanation behind an ⓘ / 🔒 tap on the profile, so the profile
/// itself stays one compact line per fact (#134, #140). [lineIcons] lead the
/// matching [lines] when set.
Future<void> showProfileInfoSheet(
  BuildContext context, {
  required String title,
  required List<String> lines,
  List<IconData?> lineIcons = const [],
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
          for (final (i, line) in lines.indexed) ...[
            SizedBox(height: tt.rowGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lineIcons.elementAtOrNull(i) case final icon?) ...[
                  Icon(
                    icon,
                    size: tt.iconSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  SizedBox(width: tt.iconTextGap),
                ],
                Expanded(
                  child: Text(line, style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
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
    this.richText,
    this.trailing,
    super.key,
  });

  final IconData icon;
  final String text;
  final String? iconTooltip;
  final VoidCallback? onIconTap;
  final VoidCallback? onTextTap;
  final Widget? trailing;

  /// Replaces [text] visually (inline icons); [text] stays the semantics
  /// fallback.
  final InlineSpan? richText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    final color = theme.colorScheme.onSurfaceVariant;
    final iconWidget = Icon(icon, size: tt.iconSize, color: color);
    final label = Text.rich(
      richText ?? TextSpan(text: text),
      semanticsLabel: richText == null ? null : text,
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
