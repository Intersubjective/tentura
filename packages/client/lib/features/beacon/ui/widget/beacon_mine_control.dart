import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/evaluation/domain/use_case/evaluation_case.dart';

import '../../data/repository/beacon_repository.dart';
import '../sheet/beacon_share_sheet.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import '../dialog/beacon_close_confirm_dialog.dart';
import '../dialog/beacon_delete_dialog.dart';
import 'beacon_overflow_menu.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final repo = GetIt.I<BeaconRepository>();
    final evaluationCase = GetIt.I<EvaluationCase>();
    return BeaconOverflowMenu(
      beacon: beacon,
      onShare: beacon.allowsForward
          ? () => unawaited(showBeaconShareSheet(context, beacon: beacon))
          : null,
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
              if (await BeaconCloseConfirmDialog.show(context) != true) {
                return;
              }
              if (!context.mounted) return;
              try {
                await evaluationCase.beaconClose(
                  beaconId: beacon.id,
                  expectedRequiresReviewWindow: beacon.helpOfferCount > 0,
                );
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(context, isError: true, text: e.toString());
                }
              }
            }
          : null,
      onCancelBeacon: beaconAllowsCancel(beacon)
          ? () async {
              await Future<void>.delayed(Duration.zero);
              if (!context.mounted) return;
              try {
                await evaluationCase.beaconCancel(beacon.id);
              } catch (e) {
                if (context.mounted) {
                  showSnackBar(context, isError: true, text: e.toString());
                }
              }
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
                fork: () => forkBeaconViaRepository(beacon),
              );
            }
          : null,
      onDelete: () async {
        await Future<void>.delayed(Duration.zero);
        if (!context.mounted) return;
        if (await BeaconDeleteDialog.show(
              context,
              status: beacon.status,
              hasEverHadCommitter: beaconDeleteBlockedByCommitters(beacon),
            ) ??
            false) {
          try {
            await repo.delete(beacon.id);
          } catch (e) {
            if (context.mounted) {
              showSnackBar(context, isError: true, text: e.toString());
            }
          }
        }
      },
    );
  }
}
