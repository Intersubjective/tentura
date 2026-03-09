import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import '../bloc/beacon_view_cubit.dart';

class BeaconMineControl extends StatelessWidget {
  const BeaconMineControl({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final beacon = beaconViewCubit.state.beacon;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Graph View
        IconButton(
          icon: const Icon(TenturaIcons.graph),
          onPressed: beacon.myVote < 0
              ? null
              : () => context.read<ScreenCubit>().showGraphFor(beacon.id),
        ),

        // Share
        ShareCodeIconButton.id(beacon.id),

        // Menu
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            // Enable / Disable
            PopupMenuItem<void>(
              onTap: beaconViewCubit.toggleEnabled,
              child: Text(
                beaconViewCubit.state.beacon.isEnabled
                    ? l10n.disableBeacon
                    : l10n.enableBeacon,
              ),
            ),
            const PopupMenuDivider(),

            // Delete
            PopupMenuItem<void>(
              onTap: () async {
                if (await BeaconDeleteDialog.show(context) ?? false) {
                  await beaconViewCubit.delete(beacon.id);
                }
              },
              child: Text(l10n.deleteBeacon),
            ),
          ],
        ),
      ],
    );
  }
}
