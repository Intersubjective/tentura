import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/domain/entity/plan_fork_copy.dart';
import 'package:tentura/features/beacon_plan/ui/widget/plan_copy_sheet.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/forward/ui/widget/lineage_suggestions_sheet.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

/// «Создать на основе этого запроса». When [sourcePlan] (loaded only for a
/// viewer inside the Request) has steps, or the source has facts the viewer
/// can read, a sheet first asks whether, and at which times, to copy the
/// plan (plan §5.11) and which facts to bring (fact continuity §6.4);
/// dismissing that sheet opens nothing.
///
/// Saves nothing (#493): the editor opens on a local copy of
/// [sourceBeaconId] and forks the server draft at the first edit or save.
Future<void> runBeaconCreateFromAction(
  BuildContext context, {
  required String sourceBeaconId,
  BeaconPlan? sourcePlan,
}) async {
  if (sourceBeaconId.isEmpty) return;
  final facts = await _readableFacts(sourceBeaconId);
  if (!context.mounted) return;
  final plan = sourcePlan;
  List<PlanStepTime>? times;
  var factIds = const <String>[];
  if ((plan != null && plan.steps.isNotEmpty) || facts.isNotEmpty) {
    final choice = await showPlanCopySheet(context, plan: plan, facts: facts);
    if (choice == null || !context.mounted) return;
    times = choice.stepTimes;
    factIds = choice.factIds;
  }
  await GetIt.I<AppNavigator>().createBeacon(
    forkSourceId: sourceBeaconId,
    forkPlanTimes: encodePlanStepTimesQuery(times),
    forkFactIds: factIds,
  );
}

/// The source's facts the viewer can read, from the fact list query. Facts
/// are optional to a copy: when they cannot be read it goes without them.
Future<List<BeaconFactCard>> _readableFacts(String beaconId) async {
  try {
    final facts = await GetIt.I<BeaconThreadsCase>().fetchFactCards(beaconId);
    return [
      for (final f in facts)
        if (f.status != BeaconFactCardStatusBits.removed) f,
    ];
  } on Object catch (e, st) {
    _log.fine('fork: facts unavailable for $beaconId', e, st);
    return const [];
  }
}

final _log = Logger('BeaconLineageOverflowActions');

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
