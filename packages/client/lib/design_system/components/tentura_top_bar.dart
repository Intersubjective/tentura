import 'package:flutter/material.dart';

import 'package:tentura/ui/widget/linear_pi_active.dart';

import '../tentura_tokens.dart';

/// Top-bar role. Both tones paint on the surface colour so the brand colour
/// stays reserved for actions and selection (UI review #195); [primary] marks
/// a home-tab root and keeps its own value so callers state intent.
enum TenturaTopBarTone { primary, surface }

enum TenturaTopBarAlignment {
  content,
  fullWidth,

  /// No horizontal screen padding: a custom [TenturaTopBar.row] owns its
  /// insets so split headers can share the body's pane edges.
  edgeToEdge,
}

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
    Widget? account,
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
      account: account,
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
    this.account,
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

  /// The account entry (an avatar icon button), always last and always at
  /// the same spot: its glyph sits on the screen gutter whether the bar has
  /// [actions] or a custom [row], so it does not shift between screens.
  final Widget? account;
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
    return LinearPiActive.builder(context, isLoading);
  }

  static double _iconEdgeCompensation(TenturaTokens tt) =>
      (tt.buttonHeight - tt.iconSize) / 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.surface;
    final fg = scheme.onSurface;

    final barIconTheme = IconThemeData(color: fg);
    // M3 IconButton ignores [IconTheme] when [IconButtonTheme.style] is null.
    // AppBar then does `iconButtonTheme.style?.copyWith(...)`, which stays null
    // and action icons fall back to onSurfaceVariant (black in light, pale in
    // dark). Seed a non-null style so both leading and actions pick up [fg].
    final barIconButtonTheme = IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: fg,
        disabledForegroundColor: fg.withValues(alpha: 0.38),
      ),
    );

    return IconButtonTheme(
      data: barIconButtonTheme,
      child: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        iconTheme: barIconTheme,
        actionsIconTheme: barIconTheme,
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
      ),
    );
  }

  Widget _contentRow() {
    final account = this.account;
    if (account == null) return _baseRow();
    return Row(
      children: [
        Expanded(child: _baseRow()),
        Transform.translate(
          offset: Offset(iconEdgeCompensation, 0),
          child: account,
        ),
      ],
    );
  }

  Widget _baseRow() {
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
            // With an account entry after them, the actions keep their
            // touch padding as the gap to it; the account takes the edge.
            offset: Offset(
              trailingIsIcon && account == null ? iconEdgeCompensation : 0,
              0,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: actions!,
              ),
            ),
          );

    // Do not wrap [title] in FittedBox: many callers pass a Row with Expanded
    // (inbox / threads), and FittedBox gives the child unbounded width.
    final middle = Padding(
      padding: EdgeInsetsDirectional.only(
        start: leading == null ? 0 : iconTextGap,
      ),
      child: centerTitle
          ? Center(child: title)
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: title,
            ),
    );

    // NavigationToolbar lays out trailing against the full width, so long
    // text actions can paint over leading. Cap trailing to the space after a
    // reserved leading slot; FittedBox.scaleDown shrinks labels to fit.
    return LayoutBuilder(
      builder: (context, constraints) {
        final leadingReserve = leading == null
            ? 0.0
            : kMinInteractiveDimension + iconTextGap;
        final trailingMax = (constraints.maxWidth - leadingReserve).clamp(
          0.0,
          double.infinity,
        );
        return Row(
          children: [
            if (toolbarLeading != null) toolbarLeading,
            Expanded(child: middle),
            if (toolbarTrailing != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: trailingMax),
                child: toolbarTrailing,
              ),
          ],
        );
      },
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
    if (alignment == TenturaTopBarAlignment.edgeToEdge) {
      return child;
    }
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
