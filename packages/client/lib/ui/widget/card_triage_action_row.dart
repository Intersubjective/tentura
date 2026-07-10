import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Owner CTA row stacks vertically below this width (`BeaconOperationalHeaderCard` chips).
const double kCardTriageActionRowNarrowMaxWidth = 380;
const double _kCardTriageActionRowIconOnlyMaxWidth = 96;

/// Triage actions for beacon cards: Offer Help primary, Forward outlined, optional
/// tertiary action on the right.
class CardTriageActionRow extends StatelessWidget {
  const CardTriageActionRow({
    required this.onForward,
    this.onOfferHelp,
    this.secondaryLabel,
    this.secondaryIcon,
    this.secondaryTooltip,
    this.onSecondary,
    super.key,
  });

  final Future<void> Function()? onOfferHelp;
  final VoidCallback onForward;
  final String? secondaryLabel;
  final IconData? secondaryIcon;

  /// Shown for icon-only tertiary (a11y / long-press hint).
  final String? secondaryTooltip;

  final Future<void> Function()? onSecondary;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = context.tt;
    final actionLabelStyle = theme.textTheme.labelLarge!;
    final hasOfferHelp = onOfferHelp != null;
    final hasSecondary =
        onSecondary != null &&
        (secondaryLabel != null || secondaryIcon != null);

    final forwardBtn = Semantics(
      identifier: TestIds.inboxForward,
      button: true,
      child: Tooltip(
        message: l10n.forwardActionTooltip,
        child: OutlinedButton.icon(
          key: TestIds.key(TestIds.inboxForward),
          onPressed: onForward,
          icon: Icon(Icons.send, size: 18, color: tt.info),
          label: Text(
            l10n.labelForward,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: tt.info,
            textStyle: actionLabelStyle.copyWith(color: tt.info),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            alignment: Alignment.center,
          ),
        ),
      ),
    );

    final offerHelpBtn = Semantics(
      identifier: TestIds.inboxOfferHelp,
      button: true,
      child: FilledButton.icon(
        key: TestIds.key(TestIds.inboxOfferHelp),
        onPressed: () async {
          await onOfferHelp?.call();
        },
        icon: const Icon(Icons.volunteer_activism_outlined, size: 20),
        label: Text(
          l10n.labelOfferHelp,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
        style: FilledButton.styleFrom(
          textStyle: actionLabelStyle.copyWith(color: scheme.onPrimary),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          alignment: Alignment.center,
        ),
      ),
    );

    final tertiaryStyle = TextButton.styleFrom(
      foregroundColor: scheme.onSurfaceVariant,
      textStyle: actionLabelStyle.copyWith(color: scheme.onSurfaceVariant),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );

    Widget? tertiary;
    if (hasSecondary) {
      Future<void> onTap() async {
        await onSecondary?.call();
      }

      if (secondaryIcon != null && secondaryLabel != null) {
        tertiary = TextButton.icon(
          style: tertiaryStyle,
          onPressed: () async {
            await onTap();
          },
          icon: Icon(secondaryIcon, size: 16),
          label: Text(
            secondaryLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else if (secondaryIcon != null) {
        final tip = secondaryTooltip?.trim();
        tertiary = Semantics(
          identifier: TestIds.inboxDismiss,
          button: true,
          child: IconButton(
            key: TestIds.key(TestIds.inboxDismiss),
            onPressed: () async {
              await onTap();
            },
            icon: Icon(secondaryIcon, size: 22),
            style: IconButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            tooltip: tip != null && tip.isNotEmpty ? tip : null,
          ),
        );
      } else {
        tertiary = TextButton(
          style: tertiaryStyle,
          onPressed: () async {
            await onTap();
          },
          child: Text(
            secondaryLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    }

    Widget compactLayout() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasOfferHelp) ...[
            offerHelpBtn,
            SizedBox(height: tt.tightGap),
          ],
          forwardBtn,
          if (hasSecondary && tertiary != null) ...[
            SizedBox(height: tt.tightGap),
            Align(
              alignment: Alignment.centerLeft,
              child: tertiary,
            ),
          ],
        ],
      );
    }

    Widget wideLayout() {
      return Row(
        children: [
          if (hasOfferHelp) ...[
            offerHelpBtn,
            const SizedBox(width: kSpacingSmall),
            forwardBtn,
          ] else
            forwardBtn,
          if (hasSecondary && tertiary != null) ...[
            const SizedBox(width: kSpacingSmall),
            tertiary,
          ],
        ],
      );
    }

    Widget iconButton({
      required IconData icon,
      required String tooltip,
      required Color color,
      required VoidCallback onPressed,
    }) {
      return Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
          tooltip: tooltip,
          style: IconButton.styleFrom(
            foregroundColor: color,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }

    Widget iconOnlyLayout() {
      final tip = secondaryTooltip?.trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasOfferHelp) ...[
            iconButton(
              icon: Icons.volunteer_activism_outlined,
              tooltip: l10n.labelOfferHelp,
              color: scheme.primary,
              onPressed: () async {
                await onOfferHelp?.call();
              },
            ),
            SizedBox(height: tt.tightGap),
          ],
          iconButton(
            icon: Icons.send,
            tooltip: l10n.forwardActionTooltip,
            color: tt.info,
            onPressed: onForward,
          ),
          if (hasSecondary && tertiary != null) ...[
            SizedBox(height: tt.tightGap),
            iconButton(
              icon: secondaryIcon ?? Icons.more_horiz,
              tooltip: tip != null && tip.isNotEmpty
                  ? tip
                  : secondaryLabel ?? '',
              color: scheme.onSurfaceVariant,
              onPressed: () async {
                await onSecondary?.call();
              },
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (maxWidth.isFinite &&
            maxWidth < _kCardTriageActionRowIconOnlyMaxWidth) {
          return iconOnlyLayout();
        }

        final useWide =
            context.windowClass != WindowClass.compact &&
            (!maxWidth.isFinite ||
                maxWidth > kCardTriageActionRowNarrowMaxWidth);

        return useWide ? wideLayout() : compactLayout();
      },
    );
  }
}
