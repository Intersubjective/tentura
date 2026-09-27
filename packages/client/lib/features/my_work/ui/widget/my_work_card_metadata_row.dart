import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_composer.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';

/// My Work list card metadata: schedule countdown + location (+ optional people).
class MyWorkCardMetadataRow extends StatelessWidget {
  const MyWorkCardMetadataRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    this.hidePeople = false,
    this.hideYou = false,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;

  /// When true, people/face-pile is omitted (shared preview already shows it).
  final bool hidePeople;

  /// When true, the YOU row is omitted: the card lists the same obligations
  /// as rows with their own CTAs right below.
  final bool hideYou;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return BeaconHudMetadataTable(
      // The card's keyline: icons on the header tile's axis, text in the
      // same column as the title and the event rows.
      leadWidth: tt.avatarSize + tt.avatarTextGap,
      leadIconExtent: tt.avatarSize,
      buildEntries: (rowWidth) => buildMyWorkHudMetadataEntries(
        context,
        rowWidth: rowWidth,
        beacon: beacon,
        viewModel: viewModel,
        currentUserId: currentUserId,
        hideLastEventMetadata: true,
        hidePeople: hidePeople,
        hideYou: hideYou,
      ),
    );
  }
}
