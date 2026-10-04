import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const double _kPopoverWidth = 360;
const double _kPopoverHeight = 400;
const double _kSheetHeightFraction = 0.45;

/// Composer emoji button. On compact windows the picker opens as a bottom
/// sheet in place of the keyboard; elsewhere as a popover above the button.
/// Either way it stays open for several picks; Esc, a tap outside or the
/// button closes it.
///
/// Picks are inserted straight into [controller] at the selection; the
/// picker's backspace removes a whole emoji. Recents and skin tone live on the
/// device (`emoji_picker_flutter`).
class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({
    required this.controller,
    this.onClosed,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;

  /// Called after the picker closes, e.g. to return focus to the composer.
  final VoidCallback? onClosed;

  final bool enabled;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final _popover = OverlayPortalController();
  final _link = LayerLink();
  final _tapGroup = Object();

  Future<void> _toggle() async {
    if (context.windowClass == WindowClass.compact) {
      // Hide the keyboard so the sheet takes its place instead of stacking.
      FocusManager.instance.primaryFocus?.unfocus();
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => _ComposerEmojiPicker(
          controller: widget.controller,
          height:
              MediaQuery.sizeOf(sheetContext).height * _kSheetHeightFraction,
        ),
      );
      widget.onClosed?.call();
      return;
    }
    if (_popover.isShowing) {
      _closePopover();
    } else {
      setState(_popover.show);
    }
  }

  void _closePopover() {
    if (!_popover.isShowing) return;
    setState(_popover.hide);
    widget.onClosed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return OverlayPortal(
      controller: _popover,
      overlayChildBuilder: _buildPopover,
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _tapGroup,
          child: Semantics(
            identifier: TestIds.roomEmojiButton,
            button: true,
            child: IconButton(
              key: TestIds.key(TestIds.roomEmojiButton),
              tooltip: l10n.composerEmojiButtonTooltip,
              onPressed: widget.enabled ? _toggle : null,
              isSelected: _popover.isShowing,
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              selectedIcon: Icon(
                Icons.emoji_emotions,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPopover(BuildContext context) {
    final tt = context.tt;
    final viewport = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(0, -tt.tightGap),
        child: TapRegion(
          groupId: _tapGroup,
          onTapOutside: (_) => _closePopover(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _closePopover,
            },
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(tt.cardRadius),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: math.min(_kPopoverWidth, viewport.width),
                child: _ComposerEmojiPicker(
                  controller: widget.controller,
                  height: math.min(_kPopoverHeight, viewport.height * 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `emoji_picker_flutter` themed from the app's color scheme and locale.
class _ComposerEmojiPicker extends StatelessWidget {
  const _ComposerEmojiPicker({
    required this.controller,
    required this.height,
  });

  final TextEditingController controller;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final background = cs.surfaceContainerLow;
    return Semantics(
      identifier: TestIds.roomEmojiPicker,
      container: true,
      child: EmojiPicker(
        textEditingController: controller,
        config: Config(
          height: height,
          locale: Localizations.localeOf(context),
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            backgroundColor: background,
            recentsLimit: 32,
            noRecents: Text(
              l10n.emojiPickerNoRecents,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          categoryViewConfig: CategoryViewConfig(
            backgroundColor: background,
            indicatorColor: cs.primary,
            iconColor: cs.onSurfaceVariant,
            iconColorSelected: cs.primary,
            backspaceColor: cs.primary,
            dividerColor: cs.outlineVariant,
          ),
          bottomActionBarConfig: BottomActionBarConfig(
            backgroundColor: background,
            buttonColor: background,
            buttonIconColor: cs.onSurfaceVariant,
          ),
          searchViewConfig: SearchViewConfig(
            backgroundColor: background,
            buttonIconColor: cs.onSurfaceVariant,
            hintText: l10n.emojiPickerSearchHint,
          ),
          skinToneConfig: SkinToneConfig(
            dialogBackgroundColor: cs.surfaceContainerHighest,
            indicatorColor: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
