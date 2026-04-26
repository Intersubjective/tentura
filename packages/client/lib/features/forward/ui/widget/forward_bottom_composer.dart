import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'forward_input_decoration.dart';

class ForwardBottomComposer extends StatelessWidget {
  const ForwardBottomComposer({
    required this.selectedIds,
    required this.noteExpanded,
    required this.onToggleNoteExpanded,
    required this.sharedNoteController,
    required this.onSharedNoteChanged,
    required this.onForward,
    super.key,
  });

  final Set<String> selectedIds;

  final bool noteExpanded;
  final VoidCallback onToggleNoteExpanded;
  final TextEditingController sharedNoteController;
  final ValueChanged<String> onSharedNoteChanged;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final enabled = onForward != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          tt.rowGap,
          tt.screenHPadding,
          tt.rowGap,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (noteExpanded) ...[
              SizedBox(height: tt.rowGap),
              SizedBox(
                height: 64,
                child: TextField(
                  controller: sharedNoteController,
                  onChanged: onSharedNoteChanged,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: tt.info,
                  style: TenturaText.body(tt.text),
                  decoration: forwardNoteInputDecoration(
                    context,
                    hintText: l10n.forwardSharedNoteHint.toLowerCase(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.expand_less, color: tt.textMuted),
                      tooltip:
                          MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: onToggleNoteExpanded,
                    ),
                  ),
                ),
              ),
            ] else ...[
              SizedBox(height: tt.rowGap),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onToggleNoteExpanded,
                  child: SizedBox(
                    height: tt.buttonHeight,
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_comment_outlined,
                          size: tt.iconSize,
                          color: tt.textMuted,
                        ),
                        SizedBox(width: tt.rowGap),
                        Text(
                          l10n.forwardAddSharedNoteCommand,
                          style: TenturaText.command(tt.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            SizedBox(height: tt.rowGap),
            SizedBox(
              height: tt.buttonHeight,
              child: OutlinedButton(
                onPressed: onForward,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, tt.buttonHeight),
                  padding: EdgeInsets.symmetric(horizontal: tt.cardPadding.top),
                  side: BorderSide(
                    color: enabled ? tt.skyBorder : tt.borderSubtle,
                  ),
                  foregroundColor: enabled ? tt.info : tt.textFaint,
                  disabledForegroundColor: tt.textFaint,
                  disabledBackgroundColor: tt.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(tt.buttonRadius),
                  ),
                  backgroundColor: enabled ? tt.surface : tt.bg,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.send,
                      size: 14,
                      color: enabled ? tt.info : tt.textFaint,
                    ),
                    SizedBox(width: tt.rowGap),
                    Text(
                      enabled
                          ? l10n.forwardToCount(selectedIds.length)
                          : l10n.selectRecipients,
                      style: TenturaText.command(
                        enabled ? tt.info : tt.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
