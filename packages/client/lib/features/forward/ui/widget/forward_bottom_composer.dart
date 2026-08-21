import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'forward_input_decoration.dart';

class ForwardBottomComposer extends StatelessWidget {
  const ForwardBottomComposer({
    required this.selectedIds,
    required this.noteExpanded,
    required this.onToggleNoteExpanded,
    required this.sharedNoteController,
    required this.onSharedNoteChanged,
    required this.onForward,
    this.showSuggestedNoteHelper = false,
    super.key,
  });

  final Set<String> selectedIds;

  final bool noteExpanded;
  final VoidCallback onToggleNoteExpanded;
  final TextEditingController sharedNoteController;
  final ValueChanged<String> onSharedNoteChanged;
  final VoidCallback? onForward;
  final bool showSuggestedNoteHelper;

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
              if (showSuggestedNoteHelper)
                Padding(
                  padding: EdgeInsets.only(bottom: tt.rowGap / 2),
                  child: Text(
                    l10n.beaconLineageSuggestedNoteHelper,
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ),
              SizedBox(
                height: 64,
                child: Semantics(
                  identifier: TestIds.forwardNote,
                  textField: true,
                  child: TextField(
                    key: TestIds.key(TestIds.forwardNote),
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
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: onToggleNoteExpanded,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: tt.rowGap),
            ],
            SizedBox(
              height: tt.buttonHeight,
              child: Semantics(
                identifier: TestIds.forwardSubmit,
                button: true,
                enabled: enabled,
                child: OutlinedButton(
                  key: TestIds.key(TestIds.forwardSubmit),
                  onPressed: onForward,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(0, tt.buttonHeight),
                    padding: EdgeInsets.symmetric(
                      horizontal: tt.cardPadding.top,
                    ),
                    side: BorderSide(
                      color: enabled ? tt.skyBorder : tt.border,
                    ),
                    foregroundColor: enabled ? tt.info : tt.textMuted,
                    disabledForegroundColor: tt.textMuted,
                    disabledBackgroundColor: tt.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tt.buttonRadius),
                    ),
                    backgroundColor: tt.surface,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.send,
                        size: tt.iconSize,
                        color: enabled ? tt.info : tt.textMuted,
                      ),
                      SizedBox(width: tt.rowGap),
                      Text(
                        enabled
                            ? l10n.forwardToCount(selectedIds.length)
                            : l10n.selectRecipients,
                        style: TenturaText.command(
                          enabled ? tt.info : tt.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
