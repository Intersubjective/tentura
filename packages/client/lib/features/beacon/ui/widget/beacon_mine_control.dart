import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/polling/ui/widget/poll_button.dart';

import '../bloc/beacon_cubit.dart';
import '../dialog/beacon_delete_dialog.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({required this.beacon, super.key});

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beaconCubit = context.read<BeaconCubit>();
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
                beaconCubit.state.beacons
                        .singleWhere((e) => e.id == beacon.id)
                        .isEnabled
                    ? l10n.disableBeacon
                    : l10n.enableBeacon,
              ),
              onTap: () async => beaconCubit.toggleEnabled(beacon.id),
            ),
            const PopupMenuDivider(),

            // Delete
            PopupMenuItem<void>(
              child: Text(l10n.deleteBeacon),
              onTap: () async {
                if (await BeaconDeleteDialog.show(context) ?? false) {
                  await beaconCubit.delete(beacon.id);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
