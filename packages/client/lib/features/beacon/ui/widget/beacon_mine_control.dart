import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/evaluation/data/repository/evaluation_repository.dart';

import '../../data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import '../dialog/beacon_close_confirm_dialog.dart';
import '../dialog/beacon_delete_dialog.dart';
import 'beacon_overflow_menu.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final repo = GetIt.I<BeaconRepository>();
    final evaluationRepo = GetIt.I<EvaluationRepository>();
    return BeaconOverflowMenu(
      beacon: beacon,
      onShare: () => unawaited(
        ShareCodeDialog.show(
          context,
          link: Uri.parse(kServerName).replace(
            queryParameters: {'id': beacon.id},
            path: kPathAppLinkView,
          ),
          header: beacon.id,
        ),
      ),
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
        try {
          final next = beacon.isListed
              ? BeaconLifecycle.closed
              : BeaconLifecycle.open;
          if (next == BeaconLifecycle.closed &&
              beacon.lifecycle == BeaconLifecycle.open) {
            await evaluationRepo.beaconCloseWithReview(beacon.id);
          } else {
            await repo.setBeaconLifecycle(next, id: beacon.id);
          }
        } catch (e) {
          if (context.mounted) {
            showSnackBar(context, isError: true, text: e.toString());
          }
        }
      },
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
      onLineageSuggestions: beaconAllowsLineageOverflow(beacon)
          ? () => runBeaconLineageSuggestionsPreview(
              context,
              beaconId: beacon.id,
            )
          : null,
      onDelete: () async {
        await Future<void>.delayed(Duration.zero);
        if (!context.mounted) return;
        if (await BeaconDeleteDialog.show(context) ?? false) {
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
