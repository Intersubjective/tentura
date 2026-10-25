import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/snack_bar_clearance.dart';
import 'package:tentura/ui/widget/one_node_button.dart';

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
    this.sendLabel,
    super.key,
  });

  final Set<String> selectedIds;

  final bool noteExpanded;
  final VoidCallback onToggleNoteExpanded;
  final TextEditingController sharedNoteController;
  final ValueChanged<String> onSharedNoteChanged;
  final VoidCallback? onForward;
  final bool showSuggestedNoteHelper;

  /// Label of the send button for `count` recipients; defaults to
  /// «Forward to {count}». It stays on the disabled button too («Send to 0»,
  /// #441, #720): the hint to pick someone is a line above it.
  final String Function(int count)? sendLabel;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final enabled = onForward != null;
    final label = (sendLabel ?? l10n.forwardToCount)(selectedIds.length);

    // Notice bars float above this composer instead of covering «Forward to
    // N» (#406).
    return SnackBarClearance(
      child: SafeArea(
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
              // Nobody picked: say what is missing beside the disabled
              // button instead of on it (#720).
              if (selectedIds.isEmpty) ...[
                Text(
                  l10n.selectRecipients,
                  textAlign: TextAlign.center,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
                SizedBox(height: tt.rowGap / 2),
              ],
              SizedBox(
                height: tt.buttonHeight,
                // The identifier sits on the button's own node: a wrapper
                // that also said `button` showed a second «Send» button
                // around the real one (#723), as in help_offer_tile.dart.
                // It also reports focus when Tab lands on it (#415), and a
                // screen reader hears why it is disabled (#720).
                child: OneNodeButton(
                  identifier: TestIds.forwardSubmit,
                  enabled: enabled,
                  label: label,
                  hint: enabled ? null : l10n.selectRecipients,
                  onTap: onForward,
                  child: OutlinedButton(
                    key: TestIds.key(TestIds.forwardSubmit),
                    onPressed: onForward,
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, tt.buttonHeight),
                      padding: EdgeInsets.symmetric(
                        horizontal: tt.cardPadding.top,
                      ),
                      // With people chosen this is the screen's one action:
                      // filled, like Forward on the Request itself.
                      // With nobody chosen it stays a button, disabled: a
                      // muted outline and no fill, so it neither reads as a
                      // section label nor as the live action (#441).
                      side: BorderSide(
                        color: enabled ? scheme.primary : tt.border,
                      ),
                      foregroundColor: enabled
                          ? scheme.onPrimary
                          : tt.textMuted,
                      disabledForegroundColor: tt.textMuted,
                      disabledBackgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tt.buttonRadius),
                      ),
                      backgroundColor: enabled
                          ? scheme.primary
                          : Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.send,
                          size: tt.iconSize,
                          color: enabled ? scheme.onPrimary : tt.textMuted,
                        ),
                        SizedBox(width: tt.rowGap),
                        Text(
                          label,
                          style: TenturaText.command(
                            enabled ? scheme.onPrimary : tt.textMuted,
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
      ),
    );
  }
}
