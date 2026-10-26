import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Free-text story of how it went, saved explicitly.
class ClosureStoryField extends StatefulWidget {
  const ClosureStoryField({
    required this.initial,
    required this.onSave,
    super.key,
  });

  final String? initial;

  /// Saves the text; completes with true when it went through.
  final Future<bool> Function(String) onSave;

  @override
  State<ClosureStoryField> createState() => _ClosureStoryFieldState();
}

class _ClosureStoryFieldState extends State<ClosureStoryField> {
  late final _controller = TextEditingController(text: widget.initial)
    ..addListener(_onEdited);

  /// The text on screen is the one last saved (#734: «Saved ✓» beside Save).
  String? _savedText;

  void _onEdited() {
    if (_savedText != null && _controller.text != _savedText) {
      setState(() => _savedText = null);
    }
  }

  Future<void> _save() async {
    final text = _controller.text;
    final ok = await widget.onSave(text);
    if (!mounted || !ok || _controller.text != text) return;
    setState(() => _savedText = text);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onEdited)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(hintText: l10n.closureAuthorStoryHint),
        ),
        const SizedBox(height: TenturaSpacing.row),
        // Wraps below Save on a narrow card rather than overflowing.
        Wrap(
          spacing: TenturaSpacing.row,
          runSpacing: TenturaSpacing.tight,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              key: const ValueKey('closure.author.story.save'),
              onPressed: _save,
              child: Text(l10n.closureAuthorStorySave),
            ),
            if (_savedText != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.closureAuthorStorySaved,
                  key: const ValueKey('closure.author.story.saved'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
