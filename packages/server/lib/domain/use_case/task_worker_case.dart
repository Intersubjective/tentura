import 'dart:async';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/domain/use_case/attention_expiry_sweep_case.dart';
import 'package:tentura_server/domain/use_case/attention_channel_delivery_case.dart';

import '../entity/task_entity.dart';
import '_use_case_base.dart';

@LazySingleton()
final class TaskWorkerCase extends UseCaseBase {
  @FactoryMethod()
  static Future<TaskWorkerCase> create(
    Env env,
    Logger logger,
    ImageRepositoryPort imageRepository,
    TaskRepositoryPort tasksRepository,
    EmailDigestCase emailDigestCase,
    NotificationOutboxRepositoryPort notificationOutbox,
    AttentionExpirySweepCase attentionExpirySweep,
    AttentionChannelDeliveryCase attentionChannelDelivery,
  ) => Future.value(
    TaskWorkerCase(
      imageRepository,
      tasksRepository,
      emailDigestCase,
      notificationOutbox,
      attentionExpirySweep: attentionExpirySweep,
      attentionChannelDelivery: attentionChannelDelivery,
      env: env,
      logger: logger,
    ),
  );

  TaskWorkerCase(
    this._imageRepository,
    this._tasksRepository,
    this._emailDigestCase,
    this._notificationOutbox, {
    AttentionExpirySweepCase? attentionExpirySweep,
    AttentionChannelDeliveryCase? attentionChannelDelivery,
    required super.env,
    required super.logger,
  }) : _attentionExpirySweep = attentionExpirySweep,
       _attentionChannelDelivery = attentionChannelDelivery;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final EmailDigestCase _emailDigestCase;

  final NotificationOutboxRepositoryPort _notificationOutbox;

  final AttentionExpirySweepCase? _attentionExpirySweep;
  final AttentionChannelDeliveryCase? _attentionChannelDelivery;

  final _runnerCompleter = Completer<void>();

  var _lastDigestSweep = DateTime.fromMillisecondsSinceEpoch(0);

  var _lastRetentionSweep = DateTime.fromMillisecondsSinceEpoch(0);

  var _lastAttentionExpirySweep = DateTime.fromMillisecondsSinceEpoch(0);
  var _lastAttentionDeliverySweep = DateTime.fromMillisecondsSinceEpoch(0);

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
