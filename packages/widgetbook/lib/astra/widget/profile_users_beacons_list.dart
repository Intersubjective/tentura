import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';

import 'package:tentura/features/beacon/ui/widget/beacon_tile.dart';

import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/deep_back_button.dart';
import 'package:tentura_widgetbook/bloc/_data.dart';

import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(
  name: 'Default',
  type: UsersBeaconsList,
  path: '[astra]/widget/beacons_list',
)
Widget beaconsListUseCase(BuildContext context) =>
    UsersBeaconsList(beacons: [beaconA, beaconB]);

class UsersBeaconsList extends StatelessWidget {
  const UsersBeaconsList({required this.beacons, super.key});

  final List<Beacon> beacons;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacons'),
        leading: const DeepBackButton(),
      ),
      body: CustomScrollView(
        slivers: [
          if (beacons.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: kPaddingAll,
                child: Text(
                  'There are no beacons yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          else
            SliverList.separated(
              key: ValueKey(beacons),
              itemCount: beacons.length,
              itemBuilder: (context, i) {
                final beacon = beacons[i];
                return Padding(
                  padding: kPaddingAll,
                  child: BeaconTile(
                    beacon: beacon,
                    isMine: false,
                    key: ValueKey(beacon),
                  ),
                );
              },
              separatorBuilder: separatorBuilder,
            ),
        ],
      ),
    );
  }
}
