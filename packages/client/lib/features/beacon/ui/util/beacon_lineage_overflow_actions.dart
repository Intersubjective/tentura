import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_fork_navigation.dart';
import 'package:tentura/features/forward/ui/widget/lineage_suggestions_sheet.dart';

/// «Создать на основе этого запроса». When [sourcePlan] (loaded only for a
/// viewer inside the Request) has steps, «Скопировать план» asks first
/// whether, and at which times, to copy them (plan §5.11); dismissing that
/// sheet makes no copy at all.
Future<void> runBeaconCreateFromAction(
  BuildContext context, {
  required Future<String?> Function() fork,
  BeaconPlan? sourcePlan,
  Future<String?> Function(List<PlanStepTime> stepTimes)? forkWithPlan,
}) async {
  final plan = sourcePlan;
  String? draftId;
  if (plan != null && plan.steps.isNotEmpty && forkWithPlan != null) {
    final choice = await showPlanCopySheet(context, plan: plan);
    if (choice == null || !context.mounted) return;
    final times = choice.stepTimes;
    draftId = times == null ? await fork() : await forkWithPlan(times);
  } else {
    draftId = await fork();
  }
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
    beacon.status != BeaconStatus.deleted;
