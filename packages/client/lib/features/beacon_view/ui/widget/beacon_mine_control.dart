import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import '../bloc/beacon_view_cubit.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({super.key});

  @override
  Widget build(BuildContext context) {
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final beacon = beaconViewCubit.state.beacon;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(TenturaIcons.graph),
          onPressed: beacon.myVote < 0
              ? null
              : () => context.read<ScreenCubit>().showGraphFor(beacon.id),
        ),
        ShareCodeIconButton.id(beacon.id),
        BeaconOverflowMenu(
          beacon: beacon,
          onEdit: beacon.lifecycle == BeaconLifecycle.open
              ? () => unawaited(
                    context.router.pushPath(
                      '$kPathBeaconNew?$kQueryBeaconEditId=${beacon.id}',
                    ),
                  )
              : null,
          onToggleLifecycle: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (beacon.isListed) {
              if (await BeaconCloseConfirmDialog.show(context) != true) {
                return;
              }
              if (!context.mounted) return;
            }
            await beaconViewCubit.toggleLifecycle();
          },
          onForward: () => unawaited(
            context.router.pushPath('$kPathForwardBeacon/${beacon.id}'),
          ),
          onViewForwards: () => unawaited(
            context.router.pushPath('$kPathBeaconForwards/${beacon.id}'),
          ),
          onForwardsGraph: () =>
              context.read<ScreenCubit>().showForwardsGraphFor(beacon.id),
          onDelete: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (await BeaconDeleteDialog.show(context) ?? false) {
              await beaconViewCubit.delete(beacon.id);
            }
          },
        ),
      ],
    );
  }
}
