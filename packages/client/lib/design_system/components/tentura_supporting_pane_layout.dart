import 'package:flutter/material.dart';

import '../tentura_spacing.dart';
import '../tentura_tokens.dart';
import 'tentura_vertical_hairline.dart';

/// Material 3 canonical "supporting pane" layout.
///
/// When the body is wide enough for both (an expanded window beside the rail;
/// see [TenturaSpacing.supportingPrimaryMinWidth]) the primary content keeps
/// its readable column and a fixed-width supporting pane sits beside it, each
/// scrolling on its own — instead of one 720 dp column of everything with
/// hundreds of dp of empty surface around it. Narrower, the same sections
/// stack in one scroll view, primary first.
class TenturaSupportingPaneLayout extends StatelessWidget {
  const TenturaSupportingPaneLayout({
    required this.primarySlivers,
    required this.supportingSlivers,
    this.onRefresh,
    super.key,
  });

  static const primaryKey = Key('tentura-supporting-layout-primary');
  static const supportingKey = Key('tentura-supporting-layout-supporting');

  final List<Widget> primarySlivers;
  final List<Widget> supportingSlivers;

  /// Pull-to-refresh for the whole page (both panes).
  final Future<void> Function()? onRefresh;

  Widget _refreshable(Widget child) => onRefresh == null
      ? child
      : RefreshIndicator.adaptive(onRefresh: onRefresh!, child: child);

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPanes = tenturaSupportingPanesFit(tt, constraints.maxWidth);
        return twoPanes ? _twoPanes(tt) : _onePane(tt);
      },
    );
  }

  Widget _onePane(TenturaTokens tt) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: tt.contentMaxWidth ?? double.infinity,
      ),
      child: _refreshable(
        CustomScrollView(
          key: primaryKey,
          slivers: [...primarySlivers, ...supportingSlivers],
        ),
      ),
    ),
  );

  Widget _twoPanes(TenturaTokens tt) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      // [TenturaSupportingPaneScope] has already widened the column to both
      // panes, so the top bar above shares these edges.
      constraints: BoxConstraints(
        maxWidth: tt.contentMaxWidth ?? double.infinity,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _refreshable(
              CustomScrollView(key: primaryKey, slivers: primarySlivers),
            ),
          ),
          SizedBox(width: tt.sectionGap),
          const TenturaVerticalHairline(),
          SizedBox(width: tt.sectionGap),
          SizedBox(
            width: TenturaSpacing.supportingPaneWidth,
            child: CustomScrollView(
              key: supportingKey,
              slivers: supportingSlivers,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Whether [width] holds a primary pane of at least
/// [TenturaSpacing.supportingPrimaryMinWidth] beside the supporting pane.
bool tenturaSupportingPanesFit(TenturaTokens tt, double width) =>
    width >=
    TenturaSpacing.supportingPrimaryMinWidth +
        TenturaSpacing.supportingPaneWidth +
        tt.sectionGap * 2;

/// Wraps a screen's [Scaffold] that uses [TenturaSupportingPaneLayout].
///
/// When both panes fit, widens [TenturaTokens.contentMaxWidth] to the primary
/// column plus the supporting pane, so the top bar's content (which follows
/// that token) sits on the same edges as the two panes below it.
///
/// A builder, not a child: the top bar must be built with a context below the
/// widened theme (an `appBar:` built from the screen's own context would keep
/// the narrow column).
class TenturaSupportingPaneScope extends StatelessWidget {
  const TenturaSupportingPaneScope({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final tt = context.tt;
      final primary = tt.contentMaxWidth;
      if (primary == null ||
          !tenturaSupportingPanesFit(tt, constraints.maxWidth)) {
        return builder(context);
      }
      final theme = Theme.of(context);
      final widened = tt.copyWith(
        contentMaxWidth:
            primary + TenturaSpacing.supportingPaneWidth + tt.sectionGap * 2,
        refreshContentMaxWidth: true,
      );
      return Theme(
        data: theme.copyWith(
          extensions: [
            widened,
            ...theme.extensions.values.where((e) => e is! TenturaTokens),
          ],
        ),
        child: Builder(builder: builder),
      );
    },
  );
}
