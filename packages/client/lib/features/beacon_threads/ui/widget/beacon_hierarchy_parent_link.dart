import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Immediate-parent link for a child request header (plan §6.1).
class BeaconHierarchyParentLink extends StatelessWidget {
  const BeaconHierarchyParentLink({
    required this.reference,
    super.key,
  });

  final BeaconParentReference reference;

  @override
  Widget build(BuildContext context) {
    return switch (reference.state) {
      BeaconParentReferenceState.none => const SizedBox.shrink(),
      BeaconParentReferenceState.unavailable => _UnavailableRow(
        label: L10n.of(context)!.beaconParentUnavailable,
      ),
      BeaconParentReferenceState.available => _AvailableRow(
        title: reference.title?.trim().isNotEmpty == true
            ? reference.title!.trim()
            : L10n.of(context)!.beaconParentRequest,
        parentBeaconId: reference.beaconId ?? '',
      ),
    };
  }
}

class _UnavailableRow extends StatelessWidget {
  const _UnavailableRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.rowGap * 0.5,
      ),
      child: Row(
        children: [
          Icon(
            Icons.link_off_outlined,
            size: tt.iconSize,
            color: tt.textMuted,
          ),
          SizedBox(width: tt.rowGap * 0.75),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailableRow extends StatelessWidget {
  const _AvailableRow({
    required this.title,
    required this.parentBeaconId,
  });

  final String title;
  final String parentBeaconId;

  @override
  Widget build(BuildContext context) {
    if (parentBeaconId.isEmpty) {
      return _UnavailableRow(label: L10n.of(context)!.beaconParentUnavailable);
    }
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    return Semantics(
      button: true,
      label: l10n.beaconParentRequest,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.router.push(BeaconViewRoute(id: parentBeaconId)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap * 0.5,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_left_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                  SizedBox(width: tt.rowGap * 0.75),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: tt.iconSize,
                    color: tt.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
