import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Reserved-width control for optional per-recipient notes on forward rows.
///
/// Every row keeps the same slot so ticking a recipient never shifts layout.
class ForwardRecipientPersonalNoteSlot extends StatelessWidget {
  const ForwardRecipientPersonalNoteSlot({
    required this.recipientName,
    required this.isSelected,
    required this.isExpanded,
    required this.notePreview,
    required this.onOpenNote,
    super.key,
  });

  final String recipientName;
  final bool isSelected;
  final bool isExpanded;
  final String? notePreview;
  final VoidCallback? onOpenNote;

  static const slotWidth = kMinInteractiveDimension;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    Widget slot = const SizedBox(
      width: slotWidth,
      height: slotWidth,
    );

    if (isSelected && !isExpanded && onOpenNote != null) {
      final trimmedPreview = notePreview?.trim();
      if (trimmedPreview != null && trimmedPreview.isNotEmpty) {
        slot = Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onOpenNote,
            borderRadius: BorderRadius.circular(TenturaRadii.button),
            child: SizedBox(
              width: slotWidth,
              height: slotWidth,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
                  child: Text(
                    trimmedPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        slot = IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: slotWidth,
            minHeight: slotWidth,
          ),
          tooltip: l10n.forwardAddPersonalNoteForName(recipientName),
          icon: Icon(Icons.add_comment_outlined, size: tt.iconSize),
          color: tt.textMuted,
          onPressed: onOpenNote,
        );
      }
    }

    return Semantics(
      button: isSelected && !isExpanded && onOpenNote != null,
      label: isSelected && !isExpanded
          ? (notePreview?.trim().isNotEmpty == true
                ? notePreview!.trim()
                : l10n.forwardAddPersonalNoteShort)
          : null,
      child: slot,
    );
  }
}

/// Expanded note field under a forward row; focuses on open and reports blur.
class ForwardRecipientExpandedPersonalNote extends StatefulWidget {
  const ForwardRecipientExpandedPersonalNote({
    required this.child,
    required this.onCollapsed,
    super.key,
  });

  final Widget child;
  final VoidCallback onCollapsed;

  @override
  State<ForwardRecipientExpandedPersonalNote> createState() =>
      _ForwardRecipientExpandedPersonalNoteState();
}

class _ForwardRecipientExpandedPersonalNoteState
    extends State<ForwardRecipientExpandedPersonalNote> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      widget.onCollapsed();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      child: widget.child,
    );
  }
}
