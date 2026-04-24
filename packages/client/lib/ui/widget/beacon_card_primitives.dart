import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

/// Font size for list-card metadata strips (My Work status line, author-line
/// middots, etc.).
const double kBeaconCardMetadataStripFontSize = 11;

/// Typography shared by [beaconCardMetadataStripSeparator] and My Work status.
TextStyle beaconCardMetadataStripTextStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  return theme.textTheme.labelSmall!.copyWith(
    fontSize: kBeaconCardMetadataStripFontSize,
    height: 1.15,
    color: scheme.onSurfaceVariant,
    fontWeight: FontWeight.w500,
  );
}

/// Middot gap between strip segments (`slot1 · slot2` style).
Widget beaconCardMetadataStripSeparator(ThemeData theme) {
  return Text(' · ', style: beaconCardMetadataStripTextStyle(theme));
}

/// Surface, shape, and optional tap target for beacon list cards.
///
/// Uses Material with ColorScheme.surfaceContainer (or [muted] / [color] overrides),
/// 8px corners, and light elevation — same for inbox and My Work. When [onTap]
/// is non-null, wraps [child] in [InkWell] for the ripple.
///
/// Put buttons and other controls in [footer] so they sit **outside** the
/// [InkWell] and do not compete with the card tap (nested [InkWell] + Material
/// buttons can otherwise both fire).
class BeaconCardShell extends StatelessWidget {
  const BeaconCardShell({
    required this.child,
    this.onTap,
    this.footer,
    this.muted = false,
    this.color,

    /// When null, uses [kPaddingAllS] (no footer) or tight top/sides padding (with footer).
    this.padding,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Placed below [child], outside the card [InkWell] when [onTap] is set.
  final Widget? footer;
  final bool muted;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFooter = footer != null;
    final mainPadding =
        padding ??
        (hasFooter
            ? const EdgeInsets.fromLTRB(
                kSpacingSmall,
                kSpacingSmall,
                kSpacingSmall,
                0,
              )
            : kPaddingAllS);
    final paddedMain = Padding(
      padding: mainPadding,
      child: child,
    );

    final bg =
        color ??
        (muted
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : scheme.surfaceContainer);

    final inkRadius = hasFooter
        ? const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          )
        : BorderRadius.circular(8);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTap != null)
          InkWell(
            onTap: onTap,
            borderRadius: inkRadius,
            child: paddedMain,
          )
        else
          paddedMain,
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kSpacingSmall,
              kSpacingSmall,
              kSpacingSmall,
              kSpacingSmall,
            ),
            child: footer,
          ),
      ],
    );

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      elevation: muted ? 0 : 0.5,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      child: body,
    );
  }
}

/// Identity tile, title column, and trailing slot (e.g. overflow menu).
///
/// [subline] is typically [Text] or a [Row] with avatar + author name.
class BeaconCardHeaderRow extends StatelessWidget {
  const BeaconCardHeaderRow({
    required this.beacon,
    required this.subline,
    required this.menu,
    this.titleMaxLines = 2,
    this.identitySize = 48,
    this.onTitleBlockTap,
    super.key,
  });

  final Beacon beacon;
  final Widget subline;
  final Widget menu;
  final int titleMaxLines;

  /// Passed to [BeaconIdentityTile] (inbox / My Work list cards use the same size).
  final double identitySize;

  /// When set (e.g. inbox), title + subline respond to tap without wrapping the menu.
  final VoidCallback? onTitleBlockTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          beacon.title.isEmpty ? '—' : beacon.title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
          maxLines: titleMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        subline,
      ],
    );
    final onTap = onTitleBlockTap;
    if (onTap != null) {
      titleBlock = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: titleBlock,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeaconIdentityTile(beacon: beacon, size: identitySize),
        const SizedBox(width: kSpacingSmall),
        Expanded(child: titleBlock),
        const SizedBox(width: 4),
        menu,
      ],
    );
  }
}

/// Uppercase rounded status chip (My Work pills + inbox lifecycle/coordination).
class BeaconCardPill extends StatelessWidget {
  const BeaconCardPill({
    required this.label,
    this.emphasized = false,
    this.backgroundColor,
    this.foregroundColor,
    this.onTap,
    super.key,
  });

  final String label;
  final bool emphasized;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg =
        backgroundColor ??
        (emphasized ? scheme.primaryContainer : scheme.surfaceContainerHigh);
    final fg =
        foregroundColor ??
        (emphasized ? scheme.onPrimaryContainer : scheme.onSurfaceVariant);
    final radius = BorderRadius.circular(999);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
      color: fg,
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: textStyle,
      ),
    );

    if (onTap == null) {
      return Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
        ),
        child: content,
      );
    }

    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      ),
    );
  }
}

/// Icon + child row for metadata strips (topic, commitments, insights).
///
/// Use [mainAxisSize] [MainAxisSize.max] with an [Expanded] child for a
/// full-width context line; default [MainAxisSize.min] fits [Wrap] children.
class BeaconCardMetaItem extends StatelessWidget {
  const BeaconCardMetaItem({
    required this.icon,
    required this.child,
    this.mainAxisSize = MainAxisSize.min,
    super.key,
  });

  final IconData icon;
  final Widget child;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        child,
      ],
    );
  }
}

String beaconCardCategoryLabel(Beacon beacon, L10n l10n) {
  final c = beacon.context.trim();
  return c.isEmpty ? l10n.inboxCategoryGeneral : c;
}

/// Topic / category line (icon + label) for beacon card headers.
///
/// Use as `BeaconCardAuthorSubline.category`, wrapped in `Flexible` by that
/// widget so the label can ellipsize when space is tight.
class BeaconCardCategoryMeta extends StatelessWidget {
  const BeaconCardCategoryMeta({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return BeaconCardMetaItem(
      icon: Icons.topic_outlined,
      mainAxisSize: MainAxisSize.max,
      child: Expanded(
        child: Text(
          beaconCardCategoryLabel(beacon, l10n),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
