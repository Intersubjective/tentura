import 'package:flutter/material.dart';

/// Shared lead-column width for beacon HUD / My Work metadata rows.
const double kBeaconHudRowLeadWidth = 32;

/// Lead icon size for beacon HUD / My Work metadata rows.
const double kBeaconHudRowIconSize = 20;

/// Minimum height for single-line HUD metadata rows (matches metadata avatar).
const double kBeaconHudRowMinHeight = 24;

/// Vertical gap between stacked HUD metadata rows (8dp rhythm).
const double kBeaconHudRowGap = 6;

/// Neutral outlined icons for aligned HUD metadata rows.
abstract final class BeaconHudRowIcons {
  static const IconData people = Icons.groups_outlined;
  static const IconData now = Icons.flag_outlined;
  static const IconData you = Icons.person_outline;
  static const IconData lastEvent = Icons.history_outlined;
}

/// Vertical alignment of the lead icon within [BeaconHudIconRow].
enum BeaconHudRowLeadAlign {
  /// Top-aligned with slight inset (multiline NOW rows).
  start,

  /// Vertically centered with single-line body (icon stays left in column).
  center,
}

/// Vertical stack of HUD metadata rows with uniform [kBeaconHudRowGap].
class BeaconHudMetadataColumn extends StatelessWidget {
  const BeaconHudMetadataColumn({
    required this.children,
    super.key,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    final spaced = <Widget>[children.first];
    for (var i = 1; i < children.length; i++) {
      spaced
        ..add(const SizedBox(height: kBeaconHudRowGap))
        ..add(children[i]);
    }

    return ClipRect(
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: spaced,
      ),
    );
  }
}

/// Fixed-width lead slot with a neutral semantic icon (always left-aligned).
class BeaconHudRowLead extends StatelessWidget {
  const BeaconHudRowLead({
    required this.icon,
    required this.semanticsLabel,
    this.align = BeaconHudRowLeadAlign.start,
    this.topInset,
    super.key,
  });

  final IconData icon;
  final String semanticsLabel;
  final BeaconHudRowLeadAlign align;

  /// Optional top inset for optical alignment (e.g. center icon on avatar).
  final double? topInset;

  static const double _startTopInset = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconWidget = Icon(
      icon,
      size: kBeaconHudRowIconSize,
      color: scheme.onSurfaceVariant,
    );

    final inset = topInset ??
        (align == BeaconHudRowLeadAlign.start ? _startTopInset : 0.0);

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: kBeaconHudRowLeadWidth,
        child: align == BeaconHudRowLeadAlign.center
            ? Align(
                alignment: Alignment.centerLeft,
                child: iconWidget,
              )
            : Padding(
                padding: EdgeInsets.only(top: inset),
                child: iconWidget,
              ),
      ),
    );
  }
}

/// HUD row: aligned lead icon column + expanded body (+ optional trailing).
class BeaconHudIconRow extends StatelessWidget {
  const BeaconHudIconRow({
    required this.leadIcon,
    required this.semanticsLabel,
    required this.body,
    this.leadAlign = BeaconHudRowLeadAlign.start,
    this.leadTopInset,
    this.minRowHeight,
    this.trailing,
    super.key,
  });

  final IconData leadIcon;
  final String semanticsLabel;
  final Widget body;
  final BeaconHudRowLeadAlign leadAlign;
  final double? leadTopInset;

  /// When set, enforces a minimum row height (single-line text rows only).
  final double? minRowHeight;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final rowAlign = leadAlign == BeaconHudRowLeadAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    final row = ClipRect(
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: rowAlign,
        children: [
          BeaconHudRowLead(
            icon: leadIcon,
            semanticsLabel: semanticsLabel,
            align: leadAlign,
            topInset: leadTopInset,
          ),
          Expanded(
            child: ClipRect(
              clipBehavior: Clip.none,
              child: body,
            ),
          ),
          ?trailing,
        ],
      ),
    );

    if (minRowHeight == null) {
      return row;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minRowHeight!),
      child: row,
    );
  }
}
