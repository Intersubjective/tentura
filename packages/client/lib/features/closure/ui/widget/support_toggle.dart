import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

/// «☆ Поддержать» / «★ Поддерживаю». A text button, so it gets hover, focus
/// and Enter/Space activation on desktop; there is no long-press.
class SupportToggle extends StatefulWidget {
  const SupportToggle({
    required this.supported,
    required this.onChanged,
    this.autofocus = false,
    super.key,
  });

  final bool supported;
  final ValueChanged<bool> onChanged;

  /// Puts keyboard focus on this toggle when the screen opens.
  final bool autofocus;

  @override
  State<SupportToggle> createState() => _SupportToggleState();
}

class _SupportToggleState extends State<SupportToggle> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // `autofocus` loses to the route scope taking focus after the first
    // frame, so ask for focus once the frame is done.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final supported = widget.supported;
    return TextButton(
      focusNode: _focusNode,
      onPressed: () => widget.onChanged(!supported),
      child: Text(
        supported ? l10n.closureHelperSupported : l10n.closureHelperSupport,
      ),
    );
  }
}
