import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_fork_navigation.dart';
import 'package:tentura/features/forward/ui/widget/lineage_suggestions_sheet.dart';

Future<void> runBeaconCreateFromAction(
  BuildContext context, {
  required Future<String?> Function() fork,
}) async {
  final draftId = await fork();
  if (!context.mounted || draftId == null || draftId.isEmpty) return;
  await navigateToForkedDraft(context, draftId);
}

Future<String?> forkBeaconViaRepository(Beacon beacon) async {
  if (!beaconAllowsLineageFork(beacon)) return null;
  final repo = GetIt.I<BeaconRepository>();
  final draft = await repo.fork(beacon.id);
  return draft.id;
}

void runBeaconLineageSuggestionsPreview(
  BuildContext context, {
  required String beaconId,
}) {
  if (beaconId.isEmpty) return;
  unawaited(
    showLineageSuggestionsPreviewSheet(context, beaconId: beaconId),
  );
}

bool beaconAllowsLineageOverflow(Beacon beacon) =>
    beacon.lifecycle != BeaconLifecycle.deleted;
