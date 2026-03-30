import 'package:get_it/get_it.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/polling/ui/widget/poll_button.dart';

import '../../data/repository/beacon_repository.dart';
import '../dialog/beacon_delete_dialog.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final repo = GetIt.I<BeaconRepository>();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Graph View
        IconButton(
          icon: const Icon(Icons.hub_outlined),
          onPressed: beacon.myVote < 0
              ? null
              : () => context.read<ScreenCubit>().showGraphFor(beacon.id),
        ),

        // Share
        ShareCodeIconButton.id(beacon.id),

        // Poll button
        PollButton(polling: beacon.polling),

        // Menu
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            // Enable / Disable
            PopupMenuItem<void>(
              child: Text(
                beacon.isListed ? l10n.disableBeacon : l10n.enableBeacon,
              ),
              onTap: () async {
                try {
                  final next = beacon.isListed
                      ? BeaconLifecycle.closed
                      : BeaconLifecycle.open;
                  await repo.setBeaconLifecycle(next, id: beacon.id);
                } catch (e) {
                  if (context.mounted) {
                    showSnackBar(context, isError: true, text: e.toString());
                  }
                }
              },
            ),
            const PopupMenuDivider(),

            // Delete
            PopupMenuItem<void>(
              child: Text(l10n.deleteBeacon),
              onTap: () async {
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
            ),
          ],
        ),
      ],
    );
  }
}
