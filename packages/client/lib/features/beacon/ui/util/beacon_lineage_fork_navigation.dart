import 'package:auto_route/auto_route.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';

/// Whether "Create from this beacon" is offered for [beacon].
bool beaconAllowsLineageFork(Beacon beacon) =>
    beacon.status != BeaconStatus.deleted;

/// Navigates to the draft editor after a successful fork.
Future<void> navigateToForkedDraft(BuildContext context, String draftId) async {
  if (!context.mounted || draftId.isEmpty) return;
  await context.router.pushPath('$kPathBeaconNew?$kQueryBeaconDraftId=$draftId');
}
