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
  final ValueChanged<String> onSave;

  @override
  State<ClosureStoryField> createState() => _ClosureStoryFieldState();
}

class _ClosureStoryFieldState extends State<ClosureStoryField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
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
        FilledButton(
          key: const ValueKey('closure.author.story.save'),
          onPressed: () => widget.onSave(_controller.text),
          child: Text(l10n.closureAuthorStorySave),
        ),
      ],
    );
  }
}
