import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/features/forward/ui/widget/lineage_suggestions_sheet.dart';

/// «Создать на основе этого запроса». When [sourcePlan] (loaded only for a
/// viewer inside the Request) has steps, «Скопировать план» asks first
/// whether, and at which times, to copy them (plan §5.11); dismissing that
/// sheet opens nothing.
///
/// Saves nothing (#493): the editor opens on a local copy of
/// [sourceBeaconId] and forks the server draft at the first edit or save.
Future<void> runBeaconCreateFromAction(
  BuildContext context, {
  required String sourceBeaconId,
  BeaconPlan? sourcePlan,
}) async {
  if (sourceBeaconId.isEmpty) return;
  final plan = sourcePlan;
  List<PlanStepTime>? times;
  if (plan != null && plan.steps.isNotEmpty) {
    final choice = await showPlanCopySheet(context, plan: plan);
    if (choice == null || !context.mounted) return;
    times = choice.stepTimes;
  }
  await context.router.push(
    BeaconCreateRoute(
      forkSourceId: sourceBeaconId,
      forkPlanTimes: encodePlanStepTimesQuery(times),
    ),
  );
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
