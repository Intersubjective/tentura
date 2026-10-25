import 'package:flutter/widgets.dart';

/// One semantics node for a button: name, hint, tap, identifier and its
/// keyboard focus (#723: a wrapper that only added `button` was read twice;
/// #415: the node must say it has focus when Tab lands on the button).
/// Used by the chat composer and the Forward footer.
class OneNodeButton extends StatefulWidget {
  const OneNodeButton({
    required this.identifier,
    required this.enabled,
    required this.label,
    required this.onTap,
    required this.child,
    this.hint,
    super.key,
  });

  final String identifier;
  final bool enabled;
  final String label;

  /// What a screen reader adds after [label], e.g. why the button is
  /// disabled (#720).
  final String? hint;
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<OneNodeButton> createState() => _OneNodeButtonState();
}

class _OneNodeButtonState extends State<OneNodeButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: widget.identifier,
    container: true,
    button: true,
    enabled: widget.enabled,
    focusable: true,
    focused: _focused,
    label: widget.label,
    hint: widget.hint,
    onTap: widget.onTap,
    excludeSemantics: true,
    // Follows the button's own focus without taking a Tab stop of its own.
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (focused) {
        if (mounted && focused != _focused) {
          setState(() => _focused = focused);
        }
      },
      child: widget.child,
    ),
  );
}
