import 'package:flutter/material.dart';

/// Primary-filled compact app bar matching Inbox (48dp toolbar, no tint).
class InboxStyleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const InboxStyleAppBar({
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    super.key,
  });

  static const double toolbarHeight = 48;

  final Widget? leading;
  final Widget title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight + (bottom?.preferredSize.height ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight,
      foregroundColor: scheme.onPrimary,
      iconTheme: IconThemeData(color: scheme.onPrimary),
      automaticallyImplyLeading: false,
      leading: leading,
      titleSpacing: 8,
      title: title,
      actions: actions,
      bottom: bottom,
    );
  }
}

/// [SliverAppBar] variant for scroll-linked screens (e.g. Profile).
class SliverInboxStyleAppBar extends StatelessWidget {
  const SliverInboxStyleAppBar({
    required this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.floating = true,
    this.snap = true,
    super.key,
  });

  final Widget? leading;
  final Widget title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool floating;
  final bool snap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverAppBar(
      floating: floating,
      snap: snap,
      backgroundColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: InboxStyleAppBar.toolbarHeight,
      foregroundColor: scheme.onPrimary,
      iconTheme: IconThemeData(color: scheme.onPrimary),
      automaticallyImplyLeading: false,
      leading: leading,
      titleSpacing: 8,
      title: title,
      actions: actions,
      bottom: bottom,
    );
  }
}
