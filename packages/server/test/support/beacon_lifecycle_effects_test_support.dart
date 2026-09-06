import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/use_case/beacon_lifecycle_effects_case.dart';
import 'package:tentura_server/env.dart';

import 'recording_beacon_hierarchy_outbox.dart';

BeaconLifecycleEffectsCase buildLifecycleEffectsCase({
  RecordingBeaconHierarchyOutbox? outbox,
}) {
  final recording = outbox ?? RecordingBeaconHierarchyOutbox();
  return BeaconLifecycleEffectsCase(
    recording,
    env: Env(environment: Environment.test),
    logger: Logger('LifecycleEffectsTest'),
  );
}
