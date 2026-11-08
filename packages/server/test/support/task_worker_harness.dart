import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/attention_capture_settlement_port.dart';
import 'package:tentura_server/domain/port/attention_channel_delivery_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_command_port.dart';
import 'package:tentura_server/domain/port/beacon_hierarchy_outbox_port.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';
import 'package:tentura_server/domain/port/beacon_plan_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/bud_anchor_sweep_port.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/capability_telemetry_port.dart';
import 'package:tentura_server/domain/port/closure_finalizer_port.dart';
import 'package:tentura_server/domain/port/closure_reminder_sweep_port.dart';
import 'package:tentura_server/domain/port/closure_repository_port.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/plan_attention_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/port/routing_mute_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/trust_publish_port.dart';
import 'package:tentura_server/domain/port/user_availability_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/domain/use_case/anchor_inherit_operation.dart';
import 'package:tentura_server/domain/use_case/attention_capture_settlement_case.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/domain/use_case/block_release_sweep_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_cell_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_telemetry_case.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/domain/use_case/deadline_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/plan_attention_case.dart';
import 'package:tentura_server/domain/use_case/plan_step_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_close_operation.dart';
import 'package:tentura_server/domain/use_case/post_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_expiry_warning_sweep_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/task_worker_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/env.dart';

import 'beacon_lifecycle_effects_test_support.dart';
import 'fake_beacon_access_guard.dart';
import 'fake_beacon_child_create_port.dart';
import 'fake_beacon_hierarchy_repository.dart';
import 'noop_commitment_query_case.dart';
import 'test_attention_harness.dart';

/// Thrown by every [TaskWorkerHarness] fake right after it logs its job, so a
/// sweep stops at its first port call and the worker moves to the next job.
final class SweepHalted implements Exception {
  const SweepHalted();
}

/// Base for the harness fakes: any call logs its job name and throws [SweepHalted].
/// A fake that should never be reached logs `unexpected:<what>`.
class _Logged {
  _Logged(List<String> log, String job) : _log = log, _job = job;

  final List<String> _log;
  final String _job;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    _log.add(_job);
    throw const SweepHalted();
  }
}

class _Tasks extends _Logged implements TaskRepositoryPort {
  _Tasks(super.log, super.job);
}

class _Images extends _Logged implements ImageRepositoryPort {
  _Images(super.log, super.job);
}

class _ImageGc extends _Logged implements ImageObjectGcPort {
  _ImageGc(super.log, super.job);
}

class _Outbox extends _Logged implements NotificationOutboxRepositoryPort {
  _Outbox(super.log, super.job);
}

class _Digest extends _Logged implements EmailDigestCase {
  _Digest(super.log, super.job);
}

class _Deliveries extends _Logged implements AttentionChannelDeliveryPort {
  _Deliveries(super.log, super.job);
}

class _Channels extends _Logged implements BeaconNotificationPort {
  _Channels(super.log, super.job);
}

class _HierarchyOutbox extends _Logged implements BeaconHierarchyOutboxPort {
  _HierarchyOutbox(super.log, super.job);
}

class _TrustMaintenance extends _Logged implements TrustMaintenancePort {
  _TrustMaintenance(super.log, super.job);
}

class _UserBlocks extends _Logged implements UserBlockRepositoryPort {
  _UserBlocks(super.log, super.job);
}

class _Cells extends _Logged implements CapabilityCellPort {
  _Cells(super.log, super.job);
}

class _RoutingMute extends _Logged implements RoutingMutePort {
  _RoutingMute(super.log, super.job);
}

class _Telemetry extends _Logged implements CapabilityTelemetryPort {
  _Telemetry(super.log, super.job);
}

class _WitnessWindow extends _Logged implements WitnessWindowPort {
  _WitnessWindow(super.log, super.job);
}

class _Availability extends _Logged implements UserAvailabilityRepositoryPort {
  _Availability(super.log, super.job);
}

class _Beacons extends _Logged implements BeaconRepositoryPort {
  _Beacons(super.log, super.job);
}

class _Publish extends _Logged implements TrustPublishPort {
  _Publish(super.log, super.job);
}

class _Closures extends _Logged implements ClosureRepositoryPort {
  _Closures(super.log, super.job);
}

class _Finalizer extends _Logged implements ClosureFinalizerPort {
  _Finalizer(super.log, super.job);
}

class _Reminders extends _Logged implements ClosureReminderSweepPort {
  _Reminders(super.log, super.job);
}

class _ForwardEdges extends _Logged implements ForwardEdgeRepositoryPort {
  _ForwardEdges(super.log, super.job);
}

class _Ledger extends _Logged implements TrustLedgerPort {
  _Ledger(super.log, super.job);
}

class _BudSweep extends _Logged implements BudAnchorSweepPort {
  _BudSweep(super.log, super.job);
}

class _Anchors extends _Logged implements ConstellationAnchorRepositoryPort {
  _Anchors(super.log, super.job);
}

class _Plans extends _Logged implements BeaconPlanRepositoryPort {
  _Plans(super.log, super.job);
}

class _Admission extends _Logged implements BeaconHierarchyCommandPort {
  _Admission(super.log, super.job);
}

class _PlanStore extends _Logged implements PlanAttentionRepositoryPort {
  _PlanStore(super.log, super.job);
}

class _PlanAttention extends _Logged implements PlanAttentionCase {
  _PlanAttention(super.log, super.job);
}

class _Captures extends _Logged implements AttentionCaptureSettlementPort {
  _Captures(super.log, super.job);
}

class _PostLock extends _Logged implements PostLockPort {
  _PostLock(super.log, super.job);
}

class _PassThroughUnitOfWork implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

/// Every collaborator [TaskWorkerCase] schedules, each built over fakes that
/// log the job's name into [runs] at the sweep's first port call.
///
/// [now] is the worker's clock: set it, call `worker.tick()`, read [runs].
final class TaskWorkerHarness {
  TaskWorkerHarness({
    this.contactResolutionSweepInterval = const Duration(minutes: 2),
    this.blockReleaseSweepInterval = const Duration(minutes: 3),
    this.planEnabled = true,
  }) {
    final log = runs;
    String unexpected(String what) => 'unexpected:$what';
    final attention = TestAttentionHarness();
    final uow = _PassThroughUnitOfWork();
    final logger = Logger('TaskWorkerHarness');
    imageRepository = _Images(log, unexpected('images'));
    imageObjectGc = _ImageGc(log, 'imageGc');
    tasksRepository = _Tasks(log, 'imageHash');
    emailDigestCase = _Digest(log, 'emailDigest');
    notificationOutbox = _Outbox(log, 'outboxRetention');
    beaconCase = BeaconCase(
      _Beacons(log, 'stageExpiry'),
      _Images(log, unexpected('beaconCase.images')),
      _ImageGc(log, unexpected('beaconCase.imageGc')),
      _Tasks(log, unexpected('beaconCase.tasks')),
      noopCommitmentQueryCase(),
      FakeBeaconAccessGuard(),
      FakeBeaconHierarchyRepository(),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
      env: env,
      logger: logger,
    );
    attentionChannelDelivery = AttentionChannelDeliveryCase(
      _Deliveries(log, 'attentionDelivery'),
      _Channels(log, unexpected('channels')),
    );
    beaconHierarchyDelivery = BeaconHierarchyDeliveryCase(
      _HierarchyOutbox(log, 'hierarchyDelivery'),
      attention.transactional,
      attention.intents,
      env: env,
      logger: logger,
    );
    trustMaintenance = _TrustMaintenance(log, 'trustMaintenance');
    blockCascade = BlockCascadeCase(
      _UserBlocks(log, 'blockCascade'),
      env: env,
      logger: logger,
    );
    blockReleaseSweep = BlockReleaseSweepCase(
      _UserBlocks(log, 'blockRelease'),
      env: env,
      logger: logger,
    );
    capabilityCellExpirySweep = CapabilityCellExpirySweepCase(
      _Cells(log, 'capabilityCellExpiry'),
      env: env,
      logger: logger,
    );
    capabilityTelemetry = CapabilityTelemetryCase(
      _RoutingMute(log, 'capabilityTelemetry'),
      _Telemetry(log, unexpected('telemetry')),
      env: env,
      logger: logger,
    );
    witnessWindow = _WitnessWindow(log, 'witnessWindowGc');
    capabilityCellPort = _Cells(log, 'capabilityGenerationGc');
    userAvailabilityCase = UserAvailabilityCase(
      _Availability(log, 'availabilityCleanup'),
      env: env,
      logger: logger,
    );
    deadlineReminderSweep = DeadlineReminderSweepCase(
      _Beacons(log, 'deadlineReminder'),
      noopCommitmentQueryCase(),
      attention.intents,
      attention.transactional,
    );
    trustPublisher = TrustPublisherCase(
      _Publish(log, 'trustPublish'),
      env: env,
      logger: logger,
    );
    closureFinalizeSweep = ClosureFinalizeSweepCase(
      unitOfWork: uow,
      closureRepository: _Closures(log, 'closureFinalize'),
      finalizer: _Finalizer(log, unexpected('finalizer')),
      env: env,
      logger: logger,
    );
    closureDraftReminderSweep = ClosureDraftReminderSweepCase(
      unitOfWork: uow,
      reminders: _Reminders(log, 'closureDraftReminder'),
      env: env,
      logger: logger,
    );
    staleRequestReminderSweep = StaleRequestReminderSweepCase(
      unitOfWork: uow,
      reminders: _Reminders(log, 'staleRequestReminder'),
      env: env,
      logger: logger,
    );
    contactResolutionSweep = ContactResolutionSweepCase(
      unitOfWork: uow,
      forwardEdgeRepository: _ForwardEdges(log, 'contactResolution'),
      trustLedger: _Ledger(log, unexpected('ledger')),
      env: env,
      logger: logger,
    );
    budAnchorSweep = BudAnchorSweepCase(
      _BudSweep(log, 'budAnchor'),
      AnchorInheritOperation(
        _Anchors(log, unexpected('anchors')),
        _BudSweep(log, unexpected('anchorInherit')),
      ),
      env: env,
      logger: logger,
    );
    planStepSweep = PlanStepSweepCase(
      _Plans(log, unexpected('plans')),
      _Admission(log, unexpected('admission')),
      _PlanStore(log, 'planStep'),
      _Closures(log, unexpected('planClosures')),
      attention.transactional,
      attention.intents,
      _PlanAttention(log, unexpected('planAttention')),
      env: env,
      logger: logger,
    );
    final postBeacons = _Beacons(log, 'postExpiry');
    postExpirySweep = PostExpirySweepCase(
      unitOfWork: uow,
      beaconRepository: postBeacons,
      postLock: _PostLock(log, unexpected('postLock')),
      postClose: PostCloseOperation(postBeacons),
      env: env,
      logger: logger,
    );
    postExpiryWarningSweep = PostExpiryWarningSweepCase(
      _Beacons(log, 'postExpiryWarning'),
      attention.intents,
      attention.transactional,
    );
    attentionCaptureSettlement = AttentionCaptureSettlementCase(
      _Captures(log, 'attentionCaptureSettlement'),
      env: env,
      logger: logger,
    );
  }

  final Duration contactResolutionSweepInterval;
  final Duration blockReleaseSweepInterval;
  final bool planEnabled;

  /// Job names in the order the worker ran them, across ticks.
  final runs = <String>[];

  /// The worker's clock.
  DateTime now = DateTime.utc(2026, 11, 8, 12);

  late final Env env = Env(
    environment: Environment.test,
    printEnv: false,
    publicOrigin: 'https://t.example',
    unsubscribeSigningSecret: 'secret',
    taskOnEmptyDelay: const Duration(milliseconds: 1),
    contactResolutionSweepInterval: contactResolutionSweepInterval,
    blockReleaseSweepInterval: blockReleaseSweepInterval,
    planEnabled: planEnabled,
  );

  late final ImageRepositoryPort imageRepository;
  late final ImageObjectGcPort imageObjectGc;
  late final TaskRepositoryPort tasksRepository;
  late final EmailDigestCase emailDigestCase;
  late final NotificationOutboxRepositoryPort notificationOutbox;
  late final BeaconCase beaconCase;
  late final AttentionChannelDeliveryCase attentionChannelDelivery;
  late final BeaconHierarchyDeliveryCase beaconHierarchyDelivery;
  late final TrustMaintenancePort trustMaintenance;
  late final BlockCascadeCase blockCascade;
  late final BlockReleaseSweepCase blockReleaseSweep;
  late final CapabilityCellExpirySweepCase capabilityCellExpirySweep;
  late final CapabilityTelemetryCase capabilityTelemetry;
  late final WitnessWindowPort witnessWindow;
  late final CapabilityCellPort capabilityCellPort;
  late final UserAvailabilityCase userAvailabilityCase;
  late final DeadlineReminderSweepCase deadlineReminderSweep;
  late final TrustPublisherCase trustPublisher;
  late final ClosureFinalizeSweepCase closureFinalizeSweep;
  late final ClosureDraftReminderSweepCase closureDraftReminderSweep;
  late final StaleRequestReminderSweepCase staleRequestReminderSweep;
  late final ContactResolutionSweepCase contactResolutionSweep;
  late final BudAnchorSweepCase budAnchorSweep;
  late final PlanStepSweepCase planStepSweep;
  late final PostExpirySweepCase postExpirySweep;
  late final PostExpiryWarningSweepCase postExpiryWarningSweep;
  late final AttentionCaptureSettlementCase attentionCaptureSettlement;

  /// A worker wired with every collaborator, reading [now] as its clock.
  late final TaskWorkerCase worker = TaskWorkerCase(
    imageRepository,
    tasksRepository,
    emailDigestCase,
    notificationOutbox,
    imageObjectGc: imageObjectGc,
    beaconCase: beaconCase,
    attentionChannelDelivery: attentionChannelDelivery,
    beaconHierarchyDelivery: beaconHierarchyDelivery,
    trustMaintenance: trustMaintenance,
    blockCascade: blockCascade,
    blockReleaseSweep: blockReleaseSweep,
    capabilityCellExpirySweep: capabilityCellExpirySweep,
    capabilityTelemetry: capabilityTelemetry,
    witnessWindow: witnessWindow,
    capabilityCellPort: capabilityCellPort,
    userAvailabilityCase: userAvailabilityCase,
    deadlineReminderSweep: deadlineReminderSweep,
    trustPublisher: trustPublisher,
    closureFinalizeSweep: closureFinalizeSweep,
    closureDraftReminderSweep: closureDraftReminderSweep,
    staleRequestReminderSweep: staleRequestReminderSweep,
    contactResolutionSweep: contactResolutionSweep,
    budAnchorSweep: budAnchorSweep,
    planStepSweep: planStepSweep,
    postExpirySweep: postExpirySweep,
    postExpiryWarningSweep: postExpiryWarningSweep,
    attentionCaptureSettlement: attentionCaptureSettlement,
    clock: () => now,
    env: env,
    logger: Logger('TaskWorkerHarness'),
  );

  /// The production factory over the same collaborators (it reads
  /// [BeaconCase] from GetIt, so this registers [beaconCase] for the call).
  Future<TaskWorkerCase> create() async {
    final getIt = GetIt.I;
    final hadBeaconCase = getIt.isRegistered<BeaconCase>();
    if (!hadBeaconCase) getIt.registerSingleton<BeaconCase>(beaconCase);
    try {
      return await TaskWorkerCase.create(
        env,
        Logger('TaskWorkerHarness'),
        imageRepository,
        imageObjectGc,
        tasksRepository,
        emailDigestCase,
        notificationOutbox,
        attentionChannelDelivery,
        beaconHierarchyDelivery,
        trustMaintenance,
        blockCascade,
        blockReleaseSweep,
        capabilityCellExpirySweep,
        capabilityTelemetry,
        witnessWindow,
        capabilityCellPort,
        userAvailabilityCase,
        deadlineReminderSweep,
        trustPublisher,
        closureFinalizeSweep,
        closureDraftReminderSweep,
        staleRequestReminderSweep,
        contactResolutionSweep,
        budAnchorSweep,
        planStepSweep,
        postExpirySweep,
        postExpiryWarningSweep,
        attentionCaptureSettlement,
      );
    } finally {
      if (!hadBeaconCase) await getIt.unregister<BeaconCase>();
    }
  }

  /// Sets the clock to [at], runs one worker tick and returns the jobs it ran.
  Future<List<String>> tickAt(DateTime at, {TaskWorkerCase? on}) async {
    now = at;
    final before = runs.length;
    await (on ?? worker).tick();
    return runs.sublist(before);
  }
}
