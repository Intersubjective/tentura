import 'package:flutter/material.dart';

import '../tentura_text.dart';
import '../tentura_tokens.dart';
import 'tentura_section_header.dart';

/// Horizontal geometry shared by [TenturaMenuGroup] and [TenturaMenuTile], so
/// the section header, the leading icons, the titles and the dividers sit on
/// the same two keylines.
extension TenturaMenuKeylines on TenturaTokens {
  /// Start of the leading icon inside the group surface.
  double get menuIconStart => cardPadding.left;

  /// Start of the title / subtitle text inside the group surface.
  double get menuTextStart => menuIconStart + iconSize + avatarTextGap;
}

/// A titled group of navigation rows on one bordered surface.
///
/// The settings and profile screens used stacks of full-width outlined
/// buttons for navigation: no chevron to say "this opens a page", 32–40 dp
/// rows, and destructive commands indistinguishable from help links. This is
/// the list form Material 3 uses for the same job.
class TenturaMenuGroup extends StatelessWidget {
  const TenturaMenuGroup({
    required this.children,
    this.title,
    super.key,
  });

  /// Section label, rendered by [TenturaSectionHeader] on the icon keyline.
  final String? title;

  /// Usually [TenturaMenuTile]s. Hidden (zero-size) children get no divider.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final rows = <Widget>[];
    for (final child in children) {
      if (rows.isNotEmpty) {
        rows.add(Divider(indent: tt.menuTextStart, height: 1));
      }
      rows.add(child);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: EdgeInsets.only(left: tt.menuIconStart),
            child: TenturaSectionHeader(label: title!),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ],
    );
  }
}

/// One navigation or command row inside a [TenturaMenuGroup].
class TenturaMenuTile extends StatelessWidget {
  const TenturaMenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.opensPage = true,
    super.key,
  });

  final IconData icon;
  final String title;

  /// Supporting line; wraps, never ellipsised.
  final String? subtitle;

  final VoidCallback? onTap;

  /// Replaces the default chevron.
  final Widget? trailing;

  /// Error-coloured icon and title, and no chevron: it acts, it does not
  /// navigate.
  final bool destructive;

  /// Whether the row shows a chevron (it opens another page or sheet).
  final bool opensPage;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final enabled = onTap != null;
    final base = destructive ? tt.danger : tt.text;
    final fg = enabled ? base : base.withValues(alpha: 0.38);
    return ListTile(
      onTap: onTap,
      enabled: enabled,
      minTileHeight: kMinInteractiveDimension + tt.rowGap,
      contentPadding: EdgeInsets.only(
        left: tt.menuIconStart,
        right: tt.rowGap,
      ),
      horizontalTitleGap: tt.avatarTextGap,
      minLeadingWidth: tt.iconSize,
      leading: Icon(
        icon,
        size: tt.iconSize,
        color: destructive ? fg : (enabled ? tt.textMuted : fg),
      ),
      title: Text(title, style: TenturaText.bodyMedium(fg)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TenturaText.bodySmall(tt.textMuted)),
      trailing:
          trailing ??
          (opensPage && !destructive
              ? Icon(Icons.chevron_right, color: tt.textFaint)
              : null),
    );
  }
}
