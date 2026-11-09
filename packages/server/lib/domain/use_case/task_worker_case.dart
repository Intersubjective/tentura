import 'dart:async';
import 'dart:typed_data';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/plan_step_sweep_case.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/attention_capture_settlement_case.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/beacon_hierarchy_delivery_case.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/domain/use_case/block_release_sweep_case.dart';
import 'package:tentura_server/domain/use_case/bud_anchor_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_cell_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_telemetry_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/domain/use_case/deadline_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/post_expiry_warning_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_draft_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/contact_resolution_sweep_case.dart';
import 'package:tentura_server/domain/use_case/closure_finalize_sweep_case.dart';
import 'package:tentura_server/domain/use_case/stale_request_reminder_sweep_case.dart';
import 'package:tentura_server/domain/use_case/trust_publisher_case.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/witness_window_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../entity/task_entity.dart';
import '_use_case_base.dart';

@LazySingleton()
final class TaskWorkerCase extends UseCaseBase {
  @FactoryMethod()
  static Future<TaskWorkerCase> create(
    Env env,
    Logger logger,
    ImageRepositoryPort imageRepository,
    ImageObjectGcPort imageObjectGc,
    TaskRepositoryPort tasksRepository,
    EmailDigestCase emailDigestCase,
    NotificationOutboxRepositoryPort notificationOutbox,
    AttentionChannelDeliveryCase attentionChannelDelivery,
    BeaconHierarchyDeliveryCase beaconHierarchyDelivery,
    TrustMaintenancePort trustMaintenance,
    BlockCascadeCase blockCascade,
    BlockReleaseSweepCase blockReleaseSweep,
    CapabilityCellExpirySweepCase capabilityCellExpirySweep,
    CapabilityTelemetryCase capabilityTelemetry,
    WitnessWindowPort witnessWindow,
    CapabilityCellPort capabilityCellPort,
    UserAvailabilityCase userAvailabilityCase,
    DeadlineReminderSweepCase deadlineReminderSweep,
    TrustPublisherCase trustPublisher,
    ClosureFinalizeSweepCase closureFinalizeSweep,
    ClosureDraftReminderSweepCase closureDraftReminderSweep,
    StaleRequestReminderSweepCase staleRequestReminderSweep,
    ContactResolutionSweepCase contactResolutionSweep,
    BudAnchorSweepCase budAnchorSweep,
    PlanStepSweepCase planStepSweep,
    PostExpirySweepCase postExpirySweep,
    PostExpiryWarningSweepCase postExpiryWarningSweep,
    AttentionCaptureSettlementCase attentionCaptureSettlement,
  ) => Future.value(
    TaskWorkerCase(
      imageRepository,
      tasksRepository,
      emailDigestCase,
      notificationOutbox,
      imageObjectGc: imageObjectGc,
      // BeaconCase is an async-preResolved singleton (see AccountProfileController's
      // UserCase comment): constructor injection here makes generated DI call
      // `getAsync` on an already-resolved sync singleton, which throws at runtime.
      beaconCase: GetIt.I<BeaconCase>(),
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
      env: env,
      logger: logger,
    ),
  );

  TaskWorkerCase(
    this._imageRepository,
    this._tasksRepository,
    this._emailDigestCase,
    this._notificationOutbox, {
    required super.env,
    required super.logger,
    this._imageObjectGc,
    this._beaconCase,
    this._attentionChannelDelivery,
    this._beaconHierarchyDelivery,
    this._trustMaintenance,
    this._blockCascade,
    this._blockReleaseSweep,
    this._capabilityCellExpirySweep,
    this._capabilityTelemetry,
    this._witnessWindow,
    this._capabilityCellPort,
    this._userAvailabilityCase,
    this._deadlineReminderSweep,
    this._trustPublisher,
    this._closureFinalizeSweep,
    this._closureDraftReminderSweep,
    this._staleRequestReminderSweep,
    this._contactResolutionSweep,
    this._budAnchorSweep,
    this._planStepSweep,
    this._postExpirySweep,
    this._postExpiryWarningSweep,
    this._attentionCaptureSettlement,
    this._clock = DateTime.timestamp,
  });

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final EmailDigestCase _emailDigestCase;

  final NotificationOutboxRepositoryPort _notificationOutbox;

  final ImageObjectGcPort? _imageObjectGc;
  final BeaconCase? _beaconCase;
  final AttentionChannelDeliveryCase? _attentionChannelDelivery;
  final BeaconHierarchyDeliveryCase? _beaconHierarchyDelivery;
  final TrustMaintenancePort? _trustMaintenance;
  final BlockCascadeCase? _blockCascade;
  final BlockReleaseSweepCase? _blockReleaseSweep;
  final CapabilityCellExpirySweepCase? _capabilityCellExpirySweep;
  final CapabilityTelemetryCase? _capabilityTelemetry;
  final WitnessWindowPort? _witnessWindow;
  final CapabilityCellPort? _capabilityCellPort;
  final UserAvailabilityCase? _userAvailabilityCase;
  final DeadlineReminderSweepCase? _deadlineReminderSweep;
  final TrustPublisherCase? _trustPublisher;
  final ClosureFinalizeSweepCase? _closureFinalizeSweep;
  final ClosureDraftReminderSweepCase? _closureDraftReminderSweep;
  final StaleRequestReminderSweepCase? _staleRequestReminderSweep;
  final ContactResolutionSweepCase? _contactResolutionSweep;
  final BudAnchorSweepCase? _budAnchorSweep;
  final PlanStepSweepCase? _planStepSweep;
  final PostExpirySweepCase? _postExpirySweep;
  final PostExpiryWarningSweepCase? _postExpiryWarningSweep;
  final AttentionCaptureSettlementCase? _attentionCaptureSettlement;

  /// Reads "now" for every cadence check; tests drive it by hand.
  final DateTime Function() _clock;

  /// Per-process identity for `image_object_gc` lease ownership (§3.4).
  final _gcLeaseOwner = generateId('W');

  final _runnerCompleter = Completer<void>();

  /// The worker's jobs in tick order. A job whose collaborator is null keeps
  /// its slot and does nothing when due.
  late final _jobs = <_Job>[
    // Trust publisher: cadence 10 s; nudge() forces the next tick.
    _Job(
      const Duration(seconds: 10),
      (_) => _trustPublisher?.runDue(),
      nudged: () => _trustPublisher?.consumeNudge() ?? false,
    ),
    // Closure finalize: epochs whose closing window has elapsed.
    _Job(const Duration(seconds: 60), (_) => _closureFinalizeSweep?.runDue()),
    // Closure draft reminder: voters whose draft differs from their commit.
    _Job(
      const Duration(hours: 1),
      (now) => _closureDraftReminderSweep?.runDue(now: now),
    ),
    // Noisy contact: forwards unanswered past their deadline.
    _Job(
      env.contactResolutionSweepInterval,
      (_) => _contactResolutionSweep?.runDue(),
    ),
    // Bud anchor inheritance (Arch §8.1): cadence 10 s; a bud nudges it.
    _Job(
      const Duration(seconds: 10),
      (_) => _budAnchorSweep?.runDue(),
      nudged: () => _budAnchorSweep?.consumeNudge() ?? false,
    ),
    // Dismiss-all captures abandoned mid-capture: resume or expire them.
    _Job(
      const Duration(minutes: 1),
      (_) => _attentionCaptureSettlement?.runDue(),
    ),
    // Weekly nudge to the author of a stale open request.
    _Job(
      const Duration(hours: 1),
      (now) => _staleRequestReminderSweep?.runDue(now: now),
    ),
    _Job(
      const Duration(seconds: 10),
      (now) => _attentionChannelDelivery?.runDue(
        workerId: 'task-worker',
        now: now,
      ),
    ),
    _Job(
      const Duration(seconds: 10),
      (now) => _beaconHierarchyDelivery?.runDue(
        workerId: 'task-worker',
        now: now,
      ),
    ),
    _Job(
      const Duration(minutes: 5),
      (now) => _deadlineReminderSweep?.runDue(now: now),
    ),
    _Job(const Duration(seconds: 30), (_) => _postExpirySweep?.runDue()),
    _Job(const Duration(minutes: 1), (_) => _postExpiryWarningSweep?.runDue()),
    // Request plan («либретто», #220) §4.5: step reminders, due, overdue.
    _Job(
      const Duration(seconds: 30),
      (now) => env.planEnabled ? _planStepSweep?.runDue(now: now) : null,
    ),
    _Job(
      const Duration(minutes: 1),
      (now) => _trustMaintenance?.runDue(now: now),
    ),
    _Job(const Duration(minutes: 1), (now) => _blockCascade?.runDue(now: now)),
    _Job(
      env.blockReleaseSweepInterval,
      (now) => _blockReleaseSweep?.runDue(now: now),
    ),
    // Calculate Image Hash: every tick.
    _Job.everyTick(_calculateImageHash),
    // Email digest sweep (self-gates per account; throttle the sweep itself).
    _Job(
      const Duration(minutes: 10),
      (now) => _emailDigestCase.runDue(now: now),
    ),
    // Notification outbox retention (delete read+emailed rows older than 30d).
    _Job(
      const Duration(hours: 6),
      (_) => _notificationOutbox.deleteSettledOlderThan(
        const Duration(days: 30),
      ),
    ),
    // Image object GC (§3.4): removes remote objects for rows already
    // deleted from the database, only after their owning transaction
    // committed.
    _Job(const Duration(seconds: 30), _collectImageObjects),
    // Beacon stage expiry (§3.3): sweeps invisible stages older than 24h.
    _Job(
      const Duration(minutes: 5),
      (now) => _beaconCase!.expireStaleStages(now: now),
    ),
    // Capability evidence cell expiry sweep (D3): bounded lease claim + rebuild.
    _Job(
      const Duration(minutes: 15),
      (now) => _capabilityCellExpirySweep?.runDue(now: now),
    ),
    // Capability telemetry (G1b): population-wide mute rate + seed renewal gauges.
    _Job(
      const Duration(minutes: 45),
      (now) => _capabilityTelemetry?.runDue(now: now),
    ),
    // Witness-window cache GC: rows past read-time TTL (storage only).
    _Job(const Duration(hours: 1), (_) => _witnessWindow?.gcStaleWindows()),
    // Orphan capability_evidence_generation GC (D3).
    _Job(
      const Duration(hours: 6),
      (_) => _capabilityCellPort?.gcOrphanGenerations(),
    ),
    // Availability stale-row janitor (hygiene only; reads stay correct without it).
    _Job(
      const Duration(hours: 6),
      (now) => _userAvailabilityCase?.cleanupExpired(now: now),
    ),
  ];

  Future<void> _calculateImageHash(DateTime _) async {
    final task = await _tasksRepository
        .acquire<TaskEntity<TaskCalculateImageHashDetails>>();
    if (task == null) return;
    try {
      final imageBytes = await _imageRepository.get(
        id: task.details.imageId,
      );
      final (:hash, :height, :width) = processImage(imageBytes);

      await _imageRepository.update(
        id: task.details.imageId,
        blurHash: hash,
        height: height,
        width: width,
      );
      await _tasksRepository.complete(task.id);
    } catch (e) {
      await _tasksRepository.fail(task.id);
      rethrow;
    }
  }

  Future<void> _collectImageObjects(DateTime now) async {
    final leases = await _imageObjectGc!.claim(
      leaseOwner: _gcLeaseOwner,
      now: now,
    );
    for (final lease in leases) {
      try {
        await _imageObjectGc.removeObject(
          imageId: lease.imageId,
          authorId: lease.authorId,
        );
        await _imageObjectGc.complete(
          imageId: lease.imageId,
          leaseOwner: _gcLeaseOwner,
        );
      } catch (e) {
        await _imageObjectGc.fail(
          imageId: lease.imageId,
          leaseOwner: _gcLeaseOwner,
          retryAt: now.add(_gcRetryBackoff(lease.attempts)),
          error: e.toString(),
        );
      }
    }
  }

  bool _canRun = true;

  Future<void> dispose() {
    _canRun = false;
    return _runnerCompleter.future;
  }

  Future<void> run() async {
    while (_canRun) {
      await Future<void>.delayed(env.taskOnEmptyDelay);
      await tick();
    }
    _runnerCompleter.complete();
  }

  /// One pass over every job, in order; a job that throws does not stop the
  /// jobs after it.
  @visibleForTesting
  Future<void> tick() async {
    for (final job in _jobs) {
      try {
        if (_canRun) await job.runIfDue(_clock);
      } catch (e) {
        if (env.isDebugModeOn) print(e);
      }
    }
  }

  /// Exponential backoff capped at 16 minutes, keyed by the post-claim
  /// attempt count returned by [ImageObjectGcPort.claim].
  static Duration _gcRetryBackoff(int attempts) {
    final capped = attempts < 1 ? 1 : (attempts > 6 ? 6 : attempts);
    return Duration(seconds: 30 * (1 << (capped - 1)));
  }

  static ({String hash, int height, int width}) processImage(
    Uint8List imageBytes, [
    int kMaxNumCompX = 8,
    int kMinNumCompX = 6,
  ]) {
    final image =
        img.decodeImage(imageBytes) ??
        (throw const FormatException('Cant decode image'));
    final numComp = image.height == image.width
        ? (x: kMaxNumCompX, y: kMaxNumCompX)
        : image.height > image.width
        ? (x: kMinNumCompX, y: kMaxNumCompX)
        : (x: kMaxNumCompX, y: kMinNumCompX);
    return (
      hash: BlurHash.encode(
        image,
        numCompX: numComp.x,
        numCompY: numComp.y,
      ).hash,
      height: image.height,
      width: image.width,
    );
  }
}

/// One scheduled job: runs when [_interval] has passed since its last run
/// (or at once when [_nudged] says so). The run is stamped before it starts,
/// so a job that throws still waits out its interval.
final class _Job {
  _Job(Duration this._interval, this._run, {this._nudged});

  /// A job with no cadence: it runs on every tick.
  _Job.everyTick(this._run) : _interval = null, _nudged = null;

  final Duration? _interval;
  final Future<void>? Function(DateTime now) _run;
  final bool Function()? _nudged;

  var _lastRun = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> runIfDue(DateTime Function() clock) async {
    final now = clock();
    final interval = _interval;
    if (interval != null &&
        !(_nudged?.call() ?? false) &&
        now.difference(_lastRun) < interval) {
      return;
    }
    _lastRun = now;
    await _run(now);
  }
}
