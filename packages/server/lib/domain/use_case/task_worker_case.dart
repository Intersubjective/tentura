import 'dart:async';
import 'dart:typed_data';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';
import 'package:tentura_server/domain/use_case/block_cascade_case.dart';
import 'package:tentura_server/domain/use_case/block_release_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_cell_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/capability_telemetry_case.dart';
import 'package:tentura_server/domain/use_case/trust_maintenance_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
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
    AttentionExpirySweepCase attentionExpirySweep,
    AttentionChannelDeliveryCase attentionChannelDelivery,
    TrustMaintenancePort trustMaintenance,
    BlockCascadeCase blockCascade,
    BlockReleaseSweepCase blockReleaseSweep,
    CapabilityCellExpirySweepCase capabilityCellExpirySweep,
    CapabilityTelemetryCase capabilityTelemetry,
    WitnessWindowPort witnessWindow,
    CapabilityCellPort capabilityCellPort,
    UserAvailabilityCase userAvailabilityCase,
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
      attentionExpirySweep: attentionExpirySweep,
      attentionChannelDelivery: attentionChannelDelivery,
      trustMaintenance: trustMaintenance,
      blockCascade: blockCascade,
      blockReleaseSweep: blockReleaseSweep,
      capabilityCellExpirySweep: capabilityCellExpirySweep,
      capabilityTelemetry: capabilityTelemetry,
      witnessWindow: witnessWindow,
      capabilityCellPort: capabilityCellPort,
      userAvailabilityCase: userAvailabilityCase,
      env: env,
      logger: logger,
    ),
  );

  TaskWorkerCase(
    this._imageRepository,
    this._tasksRepository,
    this._emailDigestCase,
    this._notificationOutbox, {
    ImageObjectGcPort? imageObjectGc,
    BeaconCase? beaconCase,
    AttentionExpirySweepCase? attentionExpirySweep,
    AttentionChannelDeliveryCase? attentionChannelDelivery,
    TrustMaintenancePort? trustMaintenance,
    BlockCascadeCase? blockCascade,
    BlockReleaseSweepCase? blockReleaseSweep,
    CapabilityCellExpirySweepCase? capabilityCellExpirySweep,
    CapabilityTelemetryCase? capabilityTelemetry,
    WitnessWindowPort? witnessWindow,
    CapabilityCellPort? capabilityCellPort,
    UserAvailabilityCase? userAvailabilityCase,
    required super.env,
    required super.logger,
  }) : _imageObjectGc = imageObjectGc,
       _beaconCase = beaconCase,
       _attentionExpirySweep = attentionExpirySweep,
       _attentionChannelDelivery = attentionChannelDelivery,
       _trustMaintenance = trustMaintenance,
       _blockCascade = blockCascade,
       _blockReleaseSweep = blockReleaseSweep,
       _capabilityCellExpirySweep = capabilityCellExpirySweep,
       _capabilityTelemetry = capabilityTelemetry,
       _witnessWindow = witnessWindow,
       _capabilityCellPort = capabilityCellPort,
       _userAvailabilityCase = userAvailabilityCase;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final EmailDigestCase _emailDigestCase;

  final NotificationOutboxRepositoryPort _notificationOutbox;

  final ImageObjectGcPort? _imageObjectGc;
  final BeaconCase? _beaconCase;
  final AttentionExpirySweepCase? _attentionExpirySweep;
  final AttentionChannelDeliveryCase? _attentionChannelDelivery;
  final TrustMaintenancePort? _trustMaintenance;
  final BlockCascadeCase? _blockCascade;
  final BlockReleaseSweepCase? _blockReleaseSweep;
  final CapabilityCellExpirySweepCase? _capabilityCellExpirySweep;
  final CapabilityTelemetryCase? _capabilityTelemetry;
  final WitnessWindowPort? _witnessWindow;
  final CapabilityCellPort? _capabilityCellPort;
  final UserAvailabilityCase? _userAvailabilityCase;

  /// Per-process identity for `image_object_gc` lease ownership (§3.4).
  final _gcLeaseOwner = generateId('W');

  final _runnerCompleter = Completer<void>();

  var _lastDigestSweep = DateTime.fromMillisecondsSinceEpoch(0);

  var _lastRetentionSweep = DateTime.fromMillisecondsSinceEpoch(0);

  var _lastAttentionExpirySweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastAttentionDeliverySweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastTrustMaintenanceSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastBlockCascadeSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastBlockReleaseSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastImageGcSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastStageExpirySweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastCapCellSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastCapTelemetrySweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastEwwGcSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastCapGenGcSweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastAvailabilityCleanupSweep = DateTime.fromMillisecondsSinceEpoch(0);

  late final _tasks = <Future<void> Function()>[
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastAttentionDeliverySweep) <
          const Duration(seconds: 10))
        return;
      _lastAttentionDeliverySweep = now;
      await _attentionChannelDelivery?.runDue(
        workerId: 'task-worker',
        now: now,
      );
    },
    // Review expiry is a system-owned status transition with atomic receipts.
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastAttentionExpirySweep) <
          const Duration(minutes: 1)) {
        return;
      }
      _lastAttentionExpirySweep = now;
      await _attentionExpirySweep!.runDue(now: now);
    },
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastTrustMaintenanceSweep) <
          const Duration(minutes: 1)) {
        return;
      }
      _lastTrustMaintenanceSweep = now;
      await _trustMaintenance?.runDue(now: now);
    },
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastBlockCascadeSweep) <
          const Duration(minutes: 1)) {
        return;
      }
      _lastBlockCascadeSweep = now;
      await _blockCascade?.runDue(now: now);
    },
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastBlockReleaseSweep) <
          env.blockReleaseSweepInterval) {
        return;
      }
      _lastBlockReleaseSweep = now;
      await _blockReleaseSweep?.runDue(now: now);
    },
    // Calculate Image Hash
    () async {
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
    },
    // Email digest sweep (self-gates per account; throttle the sweep itself).
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastDigestSweep) < const Duration(minutes: 10)) {
        return;
      }
      _lastDigestSweep = now;
      await _emailDigestCase.runDue(now: now);
    },
    // Notification outbox retention (delete read+emailed rows older than 30d).
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastRetentionSweep) < const Duration(hours: 6)) {
        return;
      }
      _lastRetentionSweep = now;
      await _notificationOutbox.deleteSettledOlderThan(
        const Duration(days: 30),
      );
    },
    // Image object GC (§3.4): removes remote objects for rows already
    // deleted from the database, only after their owning transaction
    // committed.
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastImageGcSweep) < const Duration(seconds: 30)) {
        return;
      }
      _lastImageGcSweep = now;
      final leases = await _imageObjectGc!.claim(
        leaseOwner: _gcLeaseOwner,
        now: now,
      );
      for (final lease in leases) {
        try {
          await _imageObjectGc!.removeObject(
            imageId: lease.imageId,
            authorId: lease.authorId,
          );
          await _imageObjectGc!.complete(
            imageId: lease.imageId,
            leaseOwner: _gcLeaseOwner,
          );
        } catch (e) {
          await _imageObjectGc!.fail(
            imageId: lease.imageId,
            leaseOwner: _gcLeaseOwner,
            retryAt: now.add(_gcRetryBackoff(lease.attempts)),
            error: e.toString(),
          );
        }
      }
    },
    // Beacon stage expiry (§3.3): sweeps invisible stages older than 24h.
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastStageExpirySweep) <
          const Duration(minutes: 5)) {
        return;
      }
      _lastStageExpirySweep = now;
      await _beaconCase!.expireStaleStages(now: now);
    },
    // Capability evidence cell expiry sweep (D3): bounded lease claim + rebuild.
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastCapCellSweep) < const Duration(minutes: 15)) {
        return;
      }
      _lastCapCellSweep = now;
      await _capabilityCellExpirySweep?.runDue(now: now);
    },
    // Capability telemetry (G1b): population-wide mute rate + seed renewal gauges.
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastCapTelemetrySweep) < const Duration(minutes: 45)) {
        return;
      }
      _lastCapTelemetrySweep = now;
      await _capabilityTelemetry?.runDue(now: now);
    },
    // Witness-window cache GC: rows past read-time TTL (storage only).
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastEwwGcSweep) < const Duration(hours: 1)) {
        return;
      }
      _lastEwwGcSweep = now;
      await _witnessWindow?.gcStaleWindows();
    },
    // Orphan capability_evidence_generation GC (D3).
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastCapGenGcSweep) < const Duration(hours: 6)) {
        return;
      }
      _lastCapGenGcSweep = now;
      await _capabilityCellPort?.gcOrphanGenerations();
    },
    // Availability stale-row janitor (hygiene only; reads stay correct without it).
    () async {
      final now = DateTime.timestamp();
      if (now.difference(_lastAvailabilityCleanupSweep) <
          const Duration(hours: 6)) {
        return;
      }
      _lastAvailabilityCleanupSweep = now;
      await _userAvailabilityCase?.cleanupExpired(now: now);
    },
  ];

  bool _canRun = true;

  Future<void> dispose() {
    _canRun = false;
    return _runnerCompleter.future;
  }

  Future<void> run() async {
    while (_canRun) {
      await Future<void>.delayed(env.taskOnEmptyDelay);
      for (final task in _tasks) {
        try {
          if (_canRun) await task();
        } catch (e) {
          if (env.isDebugModeOn) print(e);
        }
      }
    }
    _runnerCompleter.complete();
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
