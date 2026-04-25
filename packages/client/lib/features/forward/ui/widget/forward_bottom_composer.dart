import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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
          8,
          tt.screenHPadding,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (noteExpanded) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: TextField(
                  controller: sharedNoteController,
                  onChanged: onSharedNoteChanged,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: l10n.forwardSharedNoteHint.toLowerCase(),
                    hintStyle: TenturaText.meta(tt.textFaint),
                    filled: true,
                    fillColor: tt.surface,
                    contentPadding: const EdgeInsets.all(12),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.expand_less, color: tt.textMuted),
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: onToggleNoteExpanded,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: tt.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: tt.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: tt.skyBorder),
                    ),
                  ),
                  style: TenturaText.body(tt.text),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onToggleNoteExpanded,
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_comment_outlined,
                        size: 18,
                        color: tt.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.forwardAddSharedNoteCommand,
                        style: TenturaText.command(tt.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                onPressed: onForward,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    const SizedBox(width: 8),
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
