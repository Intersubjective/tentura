import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/author_info.dart';

import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_review_countdown_row.dart';

import 'beacon_info.dart';
import 'beacon_mine_control.dart';
import 'beacon_overflow_menu.dart';
import 'beacon_tile_control.dart';
import 'coordination_ui.dart';

class BeaconTile extends StatelessWidget {
  const BeaconTile({
    required this.beacon,
    required this.isMine,
    this.onClickTag,
    super.key,
  });

  final bool isMine;

  final Beacon beacon;

  final TagClickCallback? onClickTag;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: kPaddingAllS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context
            if (beacon.context.isNotEmpty)
              Padding(
                padding: kPaddingAllS,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.group_outlined,
                        size: 16,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          context.read<ContextCubit>().add(beacon.context),
                      child: Text(
                        beacon.context,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // User row
            if (!isMine)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Avatar and Title
                  AuthorInfo(author: beacon.author),

                  BeaconOverflowMenu(
                    beacon: beacon,
                    onForward: () => unawaited(
                      context.router.pushPath(
                        '$kPathForwardBeacon/${beacon.id}',
                      ),
                    ),
                    onViewForwards: () => unawaited(
                      context.router.pushPath(
                        '$kPathBeaconForwards/${beacon.id}',
                      ),
                    ),
                    onForwardsGraph: () => context
                        .read<ScreenCubit>()
                        .showForwardsGraphFor(beacon.id),
                    onComplaint: () =>
                        context.read<ScreenCubit>().showComplaint(beacon.id),
                  ),
                ],
              ),

            // Beacon Info
            BeaconInfo(
              beacon: beacon,
              isTitleLarge: true,
              isShowBeaconEnabled: true,
              onClickTag: onClickTag,
            ),

            Padding(
              padding: kPaddingSmallT,
              child: Text(
                coordinationStatusLabel(l10n, beacon.coordinationStatus),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: coordinationStatusColor(
                    theme.colorScheme,
                    beacon.coordinationStatus,
                  ),
                ),
              ),
            ),

            BeaconReviewCountdownRow(beacon: beacon),

            // Beacon Control
            Padding(
              key: ValueKey(beacon.id),
              padding: kPaddingSmallV,
              child: isMine
                  ? BeaconMineControl(beacon: beacon)
                  : BeaconTileControl(beacon: beacon),
            ),
          ],
        ),
      ),
    );
  }
}
