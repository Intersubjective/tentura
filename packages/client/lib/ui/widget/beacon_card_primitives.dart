import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

/// List-card layout tokens (inbox + My Work).
const double kBeaconCardShellHorizontalMargin = 8;
const double kBeaconCardBodyMinHeight = 104;
const double kBeaconCardHeaderIconSize = 40;
const double kBeaconCardMenuSlotWidth = 32;
const double kBeaconCardMenuSlotHeight = 40;
const double kBeaconCardMetadataAvatarSize = 22;

/// Font size for metadata-line middots and legacy strips.
const double kBeaconCardMetadataStripFontSize = 11;

/// Status line (slot1 · slot2 · slot3) on list cards.
const double kBeaconCardStatusLineFontSize = 12;

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

/// Typography for the full-width author / context / updated line.
TextStyle beaconCardMetadataLineTextStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  return theme.textTheme.labelSmall!.copyWith(
    fontSize: kBeaconCardMetadataStripFontSize,
    height: 1.15,
    color: scheme.onSurfaceVariant,
    fontWeight: FontWeight.w400,
  );
}

/// My Work / inbox operational status line (`committed · …`).
TextStyle beaconCardStatusLineTextStyle(ThemeData theme) {
  final scheme = theme.colorScheme;
  return theme.textTheme.labelSmall!.copyWith(
    fontSize: kBeaconCardStatusLineFontSize,
    height: 1.2,
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kBeaconCardBodyMinHeight),
        child: child,
      ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kBeaconCardShellHorizontalMargin),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        elevation: muted ? 0 : 0.5,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        child: body,
      ),
    );
  }
}

/// Avatar + author display name + context (single line). Separate from the
/// updated time row; used inside [BeaconCardMetadataLine].
class BeaconCardAuthorContextRow extends StatelessWidget {
  const BeaconCardAuthorContextRow({
    required this.author,
    required this.name,
    required this.nameStyle,
    required this.baseStyle,
    required this.category,
    super.key,
  });

  final Profile author;
  final String name;
  final TextStyle nameStyle;
  final TextStyle baseStyle;
  final String category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SelfAwareAvatar(
          profile: author,
          size: kBeaconCardMetadataAvatarSize,
          withRating: false,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: name, style: nameStyle),
                TextSpan(text: ' · ', style: baseStyle),
                TextSpan(text: category),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Author/context row (own object) plus a full-width "updated" line aligned to
/// the card content edge, not to the avatar.
class BeaconCardMetadataLine extends StatelessWidget {
  const BeaconCardMetadataLine({
    required this.beacon,
    required this.updatedLine,
    super.key,
  });

  final Beacon beacon;
  final String updatedLine;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final base = beaconCardMetadataLineTextStyle(theme);
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final isSelf = SelfUserHighlight.profileIsSelf(
          beacon.author,
          state.profile.id,
        );
        final name = SelfUserHighlight.displayName(
          l10n,
          beacon.author,
          state.profile.id,
        );
        final nameStyle = SelfUserHighlight.nameStyle(theme, base, isSelf);
        final category = beaconCardCategoryLabel(beacon, l10n);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            BeaconCardAuthorContextRow(
              author: beacon.author,
              name: name,
              nameStyle: nameStyle,
              baseStyle: base,
              category: category,
            ),
            const SizedBox(height: 4),
            Text(
              updatedLine,
              style: base,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

/// Identity tile, title, and trailing overflow (single header row; no sublines).
class BeaconCardHeaderRow extends StatelessWidget {
  const BeaconCardHeaderRow({
    required this.beacon,
    required this.menu,
    this.titleMaxLines = 2,
    this.identitySize = kBeaconCardHeaderIconSize,
    this.onTitleBlockTap,
    super.key,
  });

  final Beacon beacon;
  final Widget menu;
  final int titleMaxLines;

  /// Passed to [BeaconIdentityTile] (inbox / My Work list cards use 40px).
  final double identitySize;

  /// When set, the title [Text] opens detail without wrapping the menu.
  final VoidCallback? onTitleBlockTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const titleStyle = TextStyle(
      fontSize: 15,
      height: 1.25,
      fontWeight: FontWeight.w600,
    );

    Widget title = Text(
      beacon.title.isEmpty ? '—' : beacon.title,
      style: titleStyle.copyWith(color: scheme.onSurface),
      maxLines: titleMaxLines,
      overflow: TextOverflow.ellipsis,
    );
    final onTap = onTitleBlockTap;
    if (onTap != null) {
      title = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: title,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeaconIdentityTile(beacon: beacon, size: identitySize),
        const SizedBox(width: kSpacingSmall),
        Expanded(child: title),
        SizedBox(
          width: kBeaconCardMenuSlotWidth,
          height: kBeaconCardMenuSlotHeight,
          child: Align(
            alignment: Alignment.topRight,
            child: menu,
          ),
        ),
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
