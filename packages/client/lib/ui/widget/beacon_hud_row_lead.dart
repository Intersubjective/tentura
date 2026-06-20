import 'package:flutter/material.dart';

/// Shared lead-column width for beacon HUD / My Work metadata rows.
const double kBeaconHudRowLeadWidth = 32;

/// Lead icon size for beacon HUD / My Work metadata rows.
const double kBeaconHudRowIconSize = 20;

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

/// Fixed-width lead slot with a neutral semantic icon (always left-aligned).
class BeaconHudRowLead extends StatelessWidget {
  const BeaconHudRowLead({
    required this.icon,
    required this.semanticsLabel,
    this.align = BeaconHudRowLeadAlign.start,
    super.key,
  });

  final IconData icon;
  final String semanticsLabel;
  final BeaconHudRowLeadAlign align;

  static const double _startTopInset = 2;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconWidget = Icon(
      icon,
      size: kBeaconHudRowIconSize,
      color: scheme.onSurfaceVariant,
    );

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
                padding: const EdgeInsets.only(top: _startTopInset),
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
    this.trailing,
    super.key,
  });

  final IconData leadIcon;
  final String semanticsLabel;
  final Widget body;
  final BeaconHudRowLeadAlign leadAlign;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final rowAlign = leadAlign == BeaconHudRowLeadAlign.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Row(
      crossAxisAlignment: rowAlign,
      children: [
        BeaconHudRowLead(
          icon: leadIcon,
          semanticsLabel: semanticsLabel,
          align: leadAlign,
        ),
        Expanded(child: body),
        ?trailing,
      ],
    );
  }
}
