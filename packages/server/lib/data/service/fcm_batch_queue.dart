import 'dart:async';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_batch_aggregator.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';

/// Batches FCM notifications and flushes at most once per second.
@LazySingleton(as: FcmBatchQueuePort)
class FcmBatchQueue implements FcmBatchQueuePort {
  FcmBatchQueue(
    this._fcmRemoteRepository,
    this._logger,
  ) {
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _flush(),
    );
  }

  final FcmRemoteRepositoryPort _fcmRemoteRepository;
  final Logger _logger;

  late final Timer _timer;

  static const _aggregator = BeaconNotificationBatchAggregator();

  final _pending = <String, _FcmBatchEntry>{};

  String _batchKey({
    required String receiverId,
    required String? beaconId,
    required NotificationPriority? priority,
  }) {
    final band = priority?.batchBand ?? 'normal';
    final beacon = beaconId ?? '';
    return '$receiverId|$beacon|$band';
  }

  @override
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  }) {
    final key = _batchKey(
      receiverId: receiverId,
      beaconId: message.beaconId,
      priority: message.priority,
    );
    final existing = _pending[key];
    if (existing != null) {
      existing.latestMessage = message;
      existing.fcmTokens.addAll(fcmTokens);
      existing.count += 1;
      if (message.kind != null) {
        existing.kindCounts.update(
          message.kind!,
          (v) => v + 1,
          ifAbsent: () => 1,
        );
      }
      _logger.info(
        '[FCM] batch coalesce key=$key count=${existing.count} '
        'devices=${existing.fcmTokens.length}',
      );
    } else {
      _pending[key] = _FcmBatchEntry(
        receiverId: receiverId,
        fcmTokens: fcmTokens,
        latestMessage: message,
        kindCounts: message.kind != null
            ? {message.kind!: 1}
            : <NotificationKind, int>{},
      );
      _logger.info(
        '[FCM] batch queued key=$key devices=${fcmTokens.length} '
        'title="${message.title}"',
      );
    }
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;

    final batch = Map<String, _FcmBatchEntry>.of(_pending);
    _pending.clear();

    for (final MapEntry(key: batchKey, value: entry) in batch.entries) {
      try {
        final dominantKind = _aggregator.pickDominantKind(entry.kindCounts);
        final aggregated = _aggregator.aggregate(
          count: entry.count,
          dominantKind: dominantKind,
          latestTitle: entry.latestMessage.title,
          latestBody: entry.latestMessage.body,
          beaconTitle: null,
          kindCounts: entry.kindCounts,
        );

        final notification = entry.count > 1
            ? FcmNotificationEntity(
                title: aggregated.title,
                body: aggregated.body,
                imageUrl: entry.latestMessage.imageUrl,
                actionUrl: entry.latestMessage.actionUrl,
                beaconId: entry.latestMessage.beaconId,
                coordinationItemId: entry.latestMessage.coordinationItemId,
                kind: dominantKind,
                priority: entry.latestMessage.priority,
              )
            : entry.latestMessage;

        _logger.info(
          '[FCM] batch flush key=$batchKey receiverId=${entry.receiverId} '
          'devices=${entry.fcmTokens.length} count=${entry.count} '
          'title="${notification.title}"',
        );
        final results = await _fcmRemoteRepository.sendChatNotification(
          fcmTokens: entry.fcmTokens,
          message: notification,
        );
        final stale = results.whereType<FcmTokenNotFoundException>().length;
        _logger.info(
          '[FCM] batch sent receiverId=${entry.receiverId} '
          'staleTokens=$stale',
        );
      } catch (e) {
        _logger.severe(
          '[FcmBatchQueue] Failed to send batch for ${entry.receiverId}: $e',
        );
      }
    }
  }

  @override
  @disposeMethod
  void dispose() {
    _timer.cancel();
  }
}

class _FcmBatchEntry {
  _FcmBatchEntry({
    required this.receiverId,
    required this.fcmTokens,
    required this.latestMessage,
    required this.kindCounts,
  });

  final String receiverId;
  final Set<String> fcmTokens;
  FcmNotificationEntity latestMessage;
  int count = 1;
  Map<NotificationKind, int> kindCounts;
}
