import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> showBeaconViewUpdateStatusSheet(
  BuildContext context,
  BeaconViewState state,
  BeaconViewCubit beaconViewCubit,
) async {
    final l10n = L10n.of(context)!;
    final publicOptions = <(int, String)>[
      (0, l10n.beaconPublicStatusOpen),
      (1, l10n.beaconPublicStatusCoordinating),
      (2, l10n.beaconPublicStatusMoreHelp),
      (3, l10n.beaconPublicStatusEnoughHelp),
      (4, l10n.beaconPublicStatusClosed),
    ];
    final coordinationOptions = <(int, String)>[
      (
        BeaconCoordinationStatus.neutral.smallintValue,
        l10n.coordinationNeutral,
      ),
      (
        BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
        l10n.coordinationMoreHelpNeeded,
      ),
      (
        BeaconCoordinationStatus.enoughHelpOffered.smallintValue,
        l10n.coordinationEnoughHelp,
      ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final tt = ctx.tt;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  tt.screenHPadding,
                  tt.tightGap * 2,
                  tt.screenHPadding,
                  tt.tightGap * 2,
                ),
                child: Text(
                  l10n.beaconPublicStatusCardTitle,
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              ),
              for (final o in publicOptions)
                ListTile(
                  leading: state.beacon.publicStatus == o.$1
                      ? Icon(Icons.check, size: tt.iconSize)
                      : SizedBox(width: tt.iconSize),
                  title: Text(o.$2),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(beaconViewCubit.updatePublicStatus(o.$1));
                  },
                ),
              if (state.isBeaconMine) ...[
                Divider(height: tt.rowGap),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tt.screenHPadding,
                    tt.tightGap * 2,
                    tt.screenHPadding,
                    tt.tightGap * 2,
                  ),
                  child: Text(
                    l10n.coordinationSetOverallStatus,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                ),
                for (final o in coordinationOptions)
                  ListTile(
                    title: Text(o.$2),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        beaconViewCubit.setBeaconCoordinationStatus(
                          BeaconCoordinationStatus.fromSmallint(o.$1),
                        ),
                      );
                    },
                  ),
              ],
              SizedBox(height: tt.rowGap),
            ],
          ),
        );
      },
    );
  }
