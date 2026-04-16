import 'dart:async';
import 'package:logging/logging.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/fcm_message_entity.dart';
import 'package:tentura_server/domain/port/fcm_batch_queue_port.dart';
import 'package:tentura_server/domain/port/fcm_remote_repository_port.dart';
import 'package:tentura_server/domain/port/fcm_token_repository_port.dart';

/// Batches FCM notifications and flushes at most once per second to avoid
/// per-message HTTP calls that trigger FCM rate limiting.
@LazySingleton(as: FcmBatchQueuePort)
class FcmBatchQueue implements FcmBatchQueuePort {
  FcmBatchQueue(
    this._fcmRemoteRepository,
    this._fcmTokenRepository,
    this._logger,
  ) {
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _flush(),
    );
  }

  final FcmRemoteRepositoryPort _fcmRemoteRepository;
  final FcmTokenRepositoryPort _fcmTokenRepository;
  final Logger _logger;

  late final Timer _timer;

  /// Keyed by receiverId so multiple messages to the same user coalesce.
  final _pending = <String, _FcmBatchEntry>{};

  /// Enqueue a notification for a receiver. If the same receiver already has a
  /// pending entry, the latest message replaces the previous one and the count
  /// is incremented (for summary text).
  @override
  void enqueue({
    required String receiverId,
    required Set<String> fcmTokens,
    required FcmNotificationEntity message,
  }) {
    final existing = _pending[receiverId];
    if (existing != null) {
      existing.latestMessage = message;
      existing.fcmTokens.addAll(fcmTokens);
      existing.count += 1;
    } else {
      _pending[receiverId] = _FcmBatchEntry(
        fcmTokens: fcmTokens,
        latestMessage: message,
      );
    }
  }

  Future<void> _flush() async {
    if (_pending.isEmpty) return;

    final batch = Map<String, _FcmBatchEntry>.of(_pending);
    _pending.clear();

    for (final MapEntry(key: receiverId, value: entry) in batch.entries) {
      try {
        final notification = entry.count > 1
            ? FcmNotificationEntity(
                title: entry.latestMessage.title,
                body: 'You have ${entry.count} new messages',
                imageUrl: entry.latestMessage.imageUrl,
                actionUrl: entry.latestMessage.actionUrl,
              )
            : entry.latestMessage;

        final results = await _fcmRemoteRepository.sendChatNotification(
          fcmTokens: entry.fcmTokens,
          message: notification,
        );

        for (final e in results.whereType<FcmTokenNotFoundException>()) {
          await _fcmTokenRepository.deleteToken(e.token);
          _logger.info('[FcmBatchQueue] Deleted stale token: [${e.token}]');
        }
      } catch (e) {
        _logger.severe(
          '[FcmBatchQueue] Failed to send batch for $receiverId: $e',
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
    required this.fcmTokens,
    required this.latestMessage,
  });

  final Set<String> fcmTokens;
  FcmNotificationEntity latestMessage;
  int count = 1;
}
