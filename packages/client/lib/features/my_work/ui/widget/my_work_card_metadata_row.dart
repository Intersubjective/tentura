import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';

/// My Work list card metadata: face pile + schedule countdown + location.
class MyWorkCardMetadataRow extends StatelessWidget {
  const MyWorkCardMetadataRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    return BeaconHudMetadataTable(
      buildEntries: (rowWidth) => buildMyWorkHudMetadataEntries(
        context,
        rowWidth: rowWidth,
        beacon: beacon,
        viewModel: viewModel,
        currentUserId: currentUserId,
      ),
    );
  }
}
