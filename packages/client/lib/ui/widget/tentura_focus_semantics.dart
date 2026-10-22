import 'package:flutter/widgets.dart';

/// Builds a [Semantics] wrapper that knows whether the control inside it has
/// keyboard focus.
///
/// Many of our controls name themselves with an outer
/// `Semantics(label: ..., excludeSemantics: true)` around an `InkWell` or an
/// `IconButton`. That hides the control's own focus flags, so when Tab moves
/// focus there, no semantics node is focused: on the web the browser's
/// focused element stays on the previous control, and that control looks
/// like it takes several Tab presses (#415). Pass the `focused` value of
/// [builder] as `Semantics.focused` (null where the control is not
/// interactive) to put the focus state back on the named node.
///
/// Adds no Tab stop and no semantics node of its own.
class TenturaFocusSemantics extends StatefulWidget {
  const TenturaFocusSemantics({
    required this.builder,
    super.key,
  });

  /// `focused`: whether keyboard focus is on (or inside) the child.
  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<TenturaFocusSemantics> createState() => _TenturaFocusSemanticsState();
}

class _TenturaFocusSemanticsState extends State<TenturaFocusSemantics> {
  // Watches focus below it; never takes focus itself.
  final _tracker = FocusNode(
    debugLabel: 'TenturaFocusSemantics',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _tracker,
      includeSemantics: false,
      onFocusChange: (_) => setState(() {}),
      child: Builder(
        builder: (context) => widget.builder(context, _tracker.hasFocus),
      ),
    );
  }
}
