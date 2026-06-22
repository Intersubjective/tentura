import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/hud_multiline_body.dart';

/// HUD row: fixed-width icon lead + multiline body (+ optional edit).
///
/// When [includeLead] is false, returns [HudMultilineBody] only (for
/// [BeaconHudMetadataTable] rows where the table owns the lead icon).
class HudLabeledMultiline extends StatelessWidget {
  const HudLabeledMultiline({
    required this.leadingIcon,
    required this.semanticsLabel,
    required this.text,
    required this.mutedColor,
    this.subline,
    this.isPlaceholder = false,
    this.onEdit,
    this.editSemanticLabel,
    this.onShowDetail,
    this.showDetailSemanticLabel,
    this.includeLead = true,
    this.primaryMaxLines = HudMultilineBody.defaultPrimaryMaxLines,
    this.showTruncationHint = true,
    super.key,
  });

  final IconData leadingIcon;
  final String semanticsLabel;
  final String text;
  final String? subline;
  final Color mutedColor;
  final bool isPlaceholder;
  final VoidCallback? onEdit;
  final String? editSemanticLabel;
  final VoidCallback? onShowDetail;
  final String? showDetailSemanticLabel;

  /// When false, body-only for metadata table rows (no lead, no tap).
  final bool includeLead;
  final int primaryMaxLines;
  final bool showTruncationHint;

  @override
  Widget build(BuildContext context) {
    if (!includeLead) {
      return HudMultilineBody(
        text: text,
        subline: subline,
        mutedColor: mutedColor,
        isPlaceholder: isPlaceholder,
        primaryMaxLines: primaryMaxLines,
        showTruncationHint: showTruncationHint,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textColor =
        isPlaceholder ? scheme.onSurfaceVariant : scheme.onSurface;
    final semanticsText = subline == null ? text : '$text\n$subline';
    final primaryStyle = TenturaText.bodySmall(textColor).copyWith(height: 1.25);

    Widget buildBody(double bodyMaxWidth) {
      return HudMultilineBody(
        text: text,
        subline: subline,
        mutedColor: mutedColor,
        isPlaceholder: isPlaceholder,
        primaryMaxLines: primaryMaxLines,
        showTruncationHint: showTruncationHint,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final editReserved = onEdit != null ? HudMultilineLayout.editColumnWidth : 0.0;
        final bodyMaxWidth = constraints.maxWidth -
            kBeaconHudRowLeadWidth -
            editReserved;

        final exceeds = HudMultilineLayout.textExceedsMaxLines(
          text: text,
          style: primaryStyle,
          maxWidth: bodyMaxWidth,
          maxLines: primaryMaxLines,
        );
        final singleLine = subline == null &&
            !exceeds &&
            HudMultilineLayout.textFitsSingleLine(
              text: text,
              style: primaryStyle,
              maxWidth: bodyMaxWidth,
            );
        final leadAlign = singleLine
            ? BeaconHudRowLeadAlign.center
            : BeaconHudRowLeadAlign.start;

        final iconRow = BeaconHudIconRow(
          leadIcon: leadingIcon,
          semanticsLabel: semanticsLabel,
          leadAlign: leadAlign,
          minRowHeight: singleLine ? kBeaconHudRowMinHeight : null,
          body: buildBody(bodyMaxWidth),
        );

        final detailTarget = onShowDetail == null
            ? iconRow
            : Semantics(
                button: true,
                label: showDetailSemanticLabel ?? '$semanticsLabel $semanticsText',
                child: InkWell(
                  onTap: onShowDetail,
                  borderRadius: BorderRadius.circular(8),
                  child: iconRow,
                ),
              );

        final rowCrossAxisAlignment = singleLine
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start;

        return Row(
          crossAxisAlignment: rowCrossAxisAlignment,
          children: [
            Expanded(child: detailTarget),
            if (onEdit != null) ...[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: editSemanticLabel,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  onPressed: onEdit,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Edit affordance for NOW row inside [BeaconHudMetadataTable].
Widget hudNowRowEditButton({
  required BuildContext context,
  required VoidCallback onEdit,
  required String editSemanticLabel,
}) {
  final scheme = Theme.of(context).colorScheme;
  return SizedBox(
    width: HudMultilineLayout.editColumnWidth,
    child: Semantics(
      button: true,
      label: editSemanticLabel,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        icon: Icon(
          Icons.edit_outlined,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        onPressed: onEdit,
      ),
    ),
  );
}
