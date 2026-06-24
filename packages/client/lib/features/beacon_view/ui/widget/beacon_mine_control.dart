import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
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
          onEdit: beacon.status == BeaconStatus.open
              ? () => unawaited(
                    context.router.pushPath(
                      '$kPathBeaconNew?$kQueryBeaconEditId=${beacon.id}',
                    ),
                  )
              : null,
          onCloseBeacon: beacon.status == BeaconStatus.open
              ? () async {
                  await Future<void>.delayed(Duration.zero);
                  if (!context.mounted) return;
                  final expected =
                      expectedRequiresReviewWindowForState(beaconViewCubit.state);
                  await beaconViewCubit.closeBeacon(
                    expectedRequiresReviewWindow: expected,
                  );
                }
              : null,
          onCancelBeacon: beaconAllowsCancel(beacon)
              ? () async {
                  await Future<void>.delayed(Duration.zero);
                  if (!context.mounted) return;
                  await beaconViewCubit.cancelBeacon();
                }
              : null,
          onForward: () => unawaited(
            context.router.pushPath('$kPathForwardBeacon/${beacon.id}'),
          ),
          onForwardsGraph: () =>
              context.read<ScreenCubit>().showForwardsGraphFor(beacon.id),
          onCreateFrom: beaconAllowsLineageOverflow(beacon)
              ? () async {
                  await runBeaconCreateFromAction(
                    context,
                    fork: beaconViewCubit.forkFromThis,
                  );
                }
              : null,
          onDelete: () async {
            await Future<void>.delayed(Duration.zero);
            if (!context.mounted) return;
            if (await BeaconDeleteDialog.show(
                  context,
                  status: beacon.status,
                  hasEverHadCommitter:
                      beaconDeleteBlockedByCommitters(beacon),
                ) ??
                false) {
              await beaconViewCubit.delete(beacon.id);
            }
          },
        ),
      ],
    );
  }
}
