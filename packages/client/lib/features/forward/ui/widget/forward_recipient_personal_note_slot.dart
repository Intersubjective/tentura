import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// A collapsed note's preview may grow past the reserved slot: the person
  /// wrote it, so the shift is theirs, and three characters would be useless.
  static const previewMaxWidth = slotWidth * 3;

  /// Whether the slot shows a collapsed note's preview instead of the button.
  static bool showsPreview({
    required bool isSelected,
    required bool isExpanded,
    required String? notePreview,
  }) => isSelected && !isExpanded && (notePreview?.trim().isNotEmpty ?? false);

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: slotWidth,
                maxWidth: previewMaxWidth,
                minHeight: slotWidth,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
                child: Align(
                  widthFactor: 1,
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
  EditableTextState? _editor;
  bool _settlePending = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    // Global: collapse only once focus has settled outside (#893 r4).
    FocusManager.instance.addListener(_onFocusChange);
    // Focus the note field itself, not this wrapper (#893 r3).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      for (final descendant in _focusNode.traversalDescendants) {
        descendant.requestFocus();
        return;
      }
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Arm collapse only once the editable descendant actually takes focus.
      _editor = FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>();
      return;
    }
    if (_editor == null || _settlePending) return;
    _settlePending = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        // The shared web helper restores editing on the next frame. Observe
        // the resulting focus notifications before deciding to unmount it.
        scheduleMicrotask(_collapseAfterSettledFocus);
      })
      ..scheduleFrame();
  }

  void _collapseAfterSettledFocus() {
    _settlePending = false;
    if (!mounted || _focusNode.hasFocus) return;
    final editor = _editor;
    if (editor == null || !editor.mounted) return;
    final target = FocusManager.instance.primaryFocus;
    final movedToControl = target != null && target is! FocusScopeNode;
    if (movedToControl || editor.widget.controller.text.trim().isEmpty) {
      _collapse();
    }
  }

  void _collapse() {
    if (_editor == null) return;
    _editor = null;
    widget.onCollapsed();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _editor != null) {
      _collapse();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      onTapOutside: (_) => _collapse(),
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        child: widget.child,
      ),
    );
  }
}
