import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

/// Immediate-parent link for a child request header (plan §6.1).
///
/// A Request budded from a Post reads «Вырос из поста» above the Post's
/// title; an unreadable parent shows the generic unavailable row, whatever
/// its kind.
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
            : reference.isPost
            ? ''
            : L10n.of(context)!.beaconParentRequest,
        parentBeaconId: reference.beaconId ?? '',
        isPost: reference.isPost,
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
    this.isPost = false,
  });

  final String title;
  final String parentBeaconId;
  final bool isPost;

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
      label: isPost ? l10n.beaconGrewFromPost : l10n.beaconParentRequest,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: TestIds.key(TestIds.childRequestParentLink),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isPost)
                          Text(
                            l10n.beaconGrewFromPost,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        if (title.isNotEmpty)
                          Text(
                            title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
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
