import 'package:flutter/material.dart';

import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../tentura_tokens.dart';

enum TenturaTopBarTone { primary, surface }

enum TenturaTopBarAlignment { content, fullWidth }

class TenturaTopBar extends StatelessWidget implements PreferredSizeWidget {
  factory TenturaTopBar.of(
    BuildContext context, {
    required Widget title,
    TenturaTopBarTone tone = TenturaTopBarTone.surface,
    TenturaTopBarAlignment alignment = TenturaTopBarAlignment.content,
    Widget? leading,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    Widget? progress,
    bool centerTitle = false,
    bool? leadingIsIcon,
    bool? trailingIsIcon,
    Widget? row,
    Key? key,
  }) {
    assert(
      row == null || (leading == null && actions == null && !centerTitle),
      'Custom rows own their leading/actions/title alignment.',
    );
    final tt = context.tt;
    return TenturaTopBar._(
      key: key,
      title: title,
      tone: tone,
      alignment: alignment,
      leading: leading,
      actions: actions,
      bottom: bottom,
      progress: progress,
      centerTitle: centerTitle,
      leadingIsIcon: leadingIsIcon ?? leading != null,
      trailingIsIcon: trailingIsIcon ?? (actions?.isNotEmpty ?? false),
      row: row,
      toolbarHeight: tt.appBarHeight,
      screenHPadding: tt.screenHPadding,
      contentMaxWidth: tt.contentMaxWidth,
      iconTextGap: tt.iconTextGap,
      iconEdgeCompensation: _iconEdgeCompensation(tt),
    );
  }

  const TenturaTopBar._({
    required this.title,
    required this.tone,
    required this.alignment,
    required this.centerTitle,
    required this.leadingIsIcon,
    required this.trailingIsIcon,
    required this.toolbarHeight,
    required this.screenHPadding,
    required this.iconTextGap,
    required this.iconEdgeCompensation,
    this.leading,
    this.actions,
    this.bottom,
    this.progress,
    this.row,
    this.contentMaxWidth,
    super.key,
  });

  final Widget title;
  final TenturaTopBarTone tone;
  final TenturaTopBarAlignment alignment;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? progress;
  final bool centerTitle;
  final bool leadingIsIcon;
  final bool trailingIsIcon;
  final Widget? row;
  final double toolbarHeight;
  final double screenHPadding;
  final double? contentMaxWidth;
  final double iconTextGap;
  final double iconEdgeCompensation;

  @override
  Size get preferredSize => Size.fromHeight(
    toolbarHeight +
        (bottom?.preferredSize.height ?? 0) +
        (progress != null ? LinearPiActive.height : 0),
  );

  static Widget loadingBar(
    BuildContext context,
    bool isLoading, {
    TenturaTopBarTone tone = TenturaTopBarTone.surface,
  }) {
    if (tone == TenturaTopBarTone.primary) {
      final onPrimary = Theme.of(context).colorScheme.onPrimary;
      return LinearPiActive.builder(
        context,
        isLoading,
        color: onPrimary.withValues(alpha: 0.85),
        backgroundColor: onPrimary.withValues(alpha: 0.15),
      );
    }
    return LinearPiActive.builder(context, isLoading);
  }

  static double _iconEdgeCompensation(TenturaTokens tt) =>
      (tt.buttonHeight - tt.iconSize) / 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = tone == TenturaTopBarTone.primary
        ? scheme.primary
        : scheme.surface;
    final fg = tone == TenturaTopBarTone.primary
        ? scheme.onPrimary
        : scheme.onSurface;

    return AppBar(
      backgroundColor: bg,
      foregroundColor: fg,
      iconTheme: IconThemeData(color: fg),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: SizedBox(
        height: toolbarHeight,
        child: _aligned(
          _contentRow(),
        ),
      ),
      bottom: _bottom(),
    );
  }

  Widget _contentRow() {
    final customRow = row;
    if (customRow != null) {
      return customRow;
    }
    final toolbarLeading = leading == null
        ? null
        : Transform.translate(
            offset: Offset(leadingIsIcon ? -iconEdgeCompensation : 0, 0),
            child: leading,
          );
    final toolbarTrailing = actions == null
        ? null
        : Transform.translate(
            offset: Offset(trailingIsIcon ? iconEdgeCompensation : 0, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: actions!,
            ),
          );

    return NavigationToolbar(
      leading: toolbarLeading,
      middle: title,
      trailing: toolbarTrailing,
      centerMiddle: centerTitle,
      middleSpacing: leading == null ? 0 : iconTextGap,
    );
  }

  PreferredSizeWidget? _bottom() {
    if (bottom == null && progress == null) {
      return null;
    }
    return PreferredSize(
      preferredSize: Size.fromHeight(
        (bottom?.preferredSize.height ?? 0) +
            (progress != null ? LinearPiActive.height : 0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (bottom != null)
            _aligned(
              bottom!,
            ),
          ?progress,
        ],
      ),
    );
  }

  Widget _aligned(Widget child) {
    var current = child;
    if (alignment == TenturaTopBarAlignment.content &&
        contentMaxWidth != null) {
      current = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth!),
          child: current,
        ),
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: screenHPadding),
      child: current,
    );
  }
}
