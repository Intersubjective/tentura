import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Home's side rail beside the page, shared by Home and `HomeRailFrame`.
///
/// The [rail] is one named navigation landmark, and a «Skip to content»
/// button comes before it — first for screen readers and the first Tab stop —
/// hidden until it has focus, as on the web. Enter on it moves focus to the
/// page, so the next Tab lands on the page's first control (#500).
class HomeRailLayout extends StatefulWidget {
  const HomeRailLayout({
    required Widget this.rail,
    required this.child,
    super.key,
  }) : bottomBar = null,
       _compact = false;

  /// Compact windows: a [Scaffold] with [child] as its body and [bottomBar]
  /// (already its own navigation landmark) under it. The order is the
  /// rail's: «Skip to content», then the bar, then the page (#697). A null
  /// [bottomBar] (a pushed detail hides it) keeps the page where it is.
  const HomeRailLayout.compact({
    required this.bottomBar,
    required this.child,
    super.key,
  }) : rail = null,
       _compact = true;

  final Widget? rail;

  final Widget? bottomBar;

  /// The page beside the rail, or above the bottom bar.
  final Widget child;

  final bool _compact;

  @override
  State<HomeRailLayout> createState() => _HomeRailLayoutState();
}

class _HomeRailLayoutState extends State<HomeRailLayout> {
  final _skip = _FrameOnFocusNode(debugLabel: 'Skip to content');

  /// Holds focus after a skip; never a Tab stop itself.
  final _content = FocusNode(debugLabel: 'Home content', skipTraversal: true);

  var _skipFocused = false;

  @override
  void initState() {
    super.initState();
    _skip.addListener(_onSkipFocus);
  }

  @override
  void dispose() {
    _skip
      ..removeListener(_onSkipFocus)
      ..dispose();
    _content.dispose();
    super.dispose();
  }

  void _onSkipFocus() {
    if (_skip.hasFocus != _skipFocused) {
      setState(() => _skipFocused = _skip.hasFocus);
    }
  }

  /// The page: a marker node before it (where a skip lands), then the
  /// page's own controls.
  Widget _page() => FocusTraversalOrder(
    order: const NumericFocusOrder(2),
    child: FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusTraversalOrder(
        order: const NumericFocusOrder(0),
        child: Focus(
          focusNode: _content,
          includeSemantics: false,
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: FocusTraversalGroup(
              child: Semantics(
                sortKey: const OrdinalSortKey(2),
                container: true,
                explicitChildNodes: true,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// The navigation, after the skip and before the page.
  Widget _nav(Widget nav) => FocusTraversalOrder(
    order: const NumericFocusOrder(1),
    child: FocusTraversalGroup(child: nav),
  );

  Widget _arranged(L10n l10n) {
    if (widget._compact) {
      final bar = widget.bottomBar;
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: _page(),
        bottomNavigationBar: bar == null
            ? null
            : _nav(
                Semantics(
                  sortKey: const OrdinalSortKey(1),
                  container: true,
                  explicitChildNodes: true,
                  child: bar,
                ),
              ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nav(
          Semantics(
            sortKey: const OrdinalSortKey(1),
            role: SemanticsRole.navigation,
            label: l10n.homeNavLandmark,
            container: true,
            explicitChildNodes: true,
            child: widget.rail,
          ),
        ),
        const TenturaVerticalHairline(),
        Expanded(child: _page()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final gap = context.tt.cardGap;
    return Actions(
      actions: {NextFocusIntent: _FirstTabToSkipAction(_skip)},
      // Explicit order: skip, navigation, then the page.
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Stack(
          children: [
            _arranged(l10n),
            PositionedDirectional(
              start: _skipFocused ? gap : 0,
              top: _skipFocused ? gap : 0,
              child: FocusTraversalOrder(
                order: const NumericFocusOrder(0),
                // Until focused: transparent and clipped to one pixel in the
                // window corner, still in the semantics tree. The clip bounds
                // the semantics rect too — on web that rect is a clickable
                // element, and at full size it swallowed clicks on the first
                // rail destination.
                child: SizedBox(
                  width: _skipFocused ? null : 1,
                  height: _skipFocused ? null : 1,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.topStart,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      fit: OverflowBoxFit.deferToChild,
                      child: Semantics(
                        sortKey: const OrdinalSortKey(0),
                        container: true,
                        child: Opacity(
                          opacity: _skipFocused ? 1 : 0,
                          alwaysIncludeSemantics: true,
                          child: FilledButton(
                            focusNode: _skip,
                            onPressed: _content.requestFocus,
                            child: Text(l10n.skipToContent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a frame when focus is requested, so the skip button is shown in
/// the very next frame however focus got there — a screen reader's focus
/// action (semantics) schedules no frame of its own, and focus changes apply
/// in a microtask after it.
class _FrameOnFocusNode extends FocusNode {
  _FrameOnFocusNode({super.debugLabel});

  @override
  void requestFocus([FocusNode? node]) {
    SchedulerBinding.instance.ensureVisualUpdate();
    super.requestFocus(node);
  }
}

/// Tab while nothing in particular is focused — Home's tab pages sit in
/// nested navigators whose route scope takes focus on open, so a plain Tab
/// would search only the page — goes to «Skip to content».
class _FirstTabToSkipAction extends NextFocusAction {
  _FirstTabToSkipAction(this._skip);

  final FocusNode _skip;

  @override
  bool invoke(NextFocusIntent intent) {
    final focus = primaryFocus;
    if (focus is FocusScopeNode &&
        focus.focusedChild == null &&
        _skip.canRequestFocus) {
      _skip.requestFocus();
      return true;
    }
    return super.invoke(intent);
  }
}
