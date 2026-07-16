import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/env.dart';

/// QA-only parity telemetry during the legacy Notification Center transition.
///
/// This deliberately compares both read axes over the legacy guarded page first.
/// Policy differences are reported separately so only unknown divergence gates T-15.
@injectable
final class AttentionShadowCase {
  AttentionShadowCase(
    this._outbox,
    this._guard,
    this._attention,
    this._env,
    this._logger,
  );

  final NotificationOutboxRepositoryPort _outbox;
  final BeaconAccessGuard _guard;
  final AttentionQueryPort _attention;
  final Env _env;
  final Logger _logger;

  Future<void> observeLegacyPage({
    required String accountId,
    required int limit,
    DateTime? before,
  }) async {
    if (!_env.attentionV1ShadowEnabled) return;
    try {
      final boundedLimit = limit.clamp(1, 100);
      final legacy = await _legacyPage(
        accountId: accountId,
        limit: boundedLimit,
        before: before,
      );
      final attention = await _attention.attentionFeed(
        accountId: accountId,
        view: AttentionFeedView.all,
        limit: boundedLimit,
      );
      final stableLegacy = await _legacyPage(
        accountId: accountId,
        limit: boundedLimit,
        before: before,
      );
      if (legacyReadAxesChanged(legacy, stableLegacy)) {
        _logger.info('attention_event=shadow_snapshot_race');
        return;
      }
      final result = compare(stableLegacy, attention.page.items);
      if (result.expectedTotal > 0) {
        _logger.info(
          'attention_event=shadow_delta '
          'authorization=${result.authorization} '
          'new_class=${result.newClass} mute=${result.mute}',
        );
      }
      if (result.unexplained > 0) {
        _logger.warning(
          'attention_event=shadow_mismatch '
          'unexplained=${result.unexplained} '
          'read_axis=${result.readAxisMismatch} '
          'legacy_only=${result.legacyOnly} '
          'attention_only=${result.attentionOnly}',
        );
      }
    } catch (error, stackTrace) {
      _logger.warning('attention_event=shadow_failure', error, stackTrace);
    }
  }

  Future<List<NotificationOutboxItemEntity>> _legacyPage({
    required String accountId,
    required int limit,
    required DateTime? before,
  }) async => filterBeaconNotifications(
    guard: _guard,
    viewerId: accountId,
    items: await _outbox.feedForAccount(
      accountId: accountId,
      limit: limit,
      before: before,
    ),
  );

  static bool legacyReadAxesChanged(
    Iterable<NotificationOutboxItemEntity> before,
    Iterable<NotificationOutboxItemEntity> after,
  ) {
    final beforeById = {
      for (final receipt in before) receipt.id: receipt.readAt,
    };
    final afterById = {for (final receipt in after) receipt.id: receipt.readAt};
    return beforeById.length != afterById.length ||
        beforeById.entries.any((entry) => afterById[entry.key] != entry.value);
  }

  static AttentionShadowResult compare(
    Iterable<NotificationOutboxItemEntity> legacy,
    Iterable<AttentionReceipt> attention,
  ) {
    final legacyById = {for (final receipt in legacy) receipt.id: receipt};
    final attentionById = {
      for (final receipt in attention) receipt.id: receipt,
    };
    var readAxisMismatch = 0;
    for (final id in legacyById.keys.toSet().intersection(
      attentionById.keys.toSet(),
    )) {
      if ((legacyById[id]!.readAt == null) !=
          (attentionById[id]!.seenAt == null)) {
        readAxisMismatch += 1;
      }
    }

    var authorization = 0;
    var newClass = 0;
    var mute = 0;
    var unexplained = readAxisMismatch;
    var legacyOnly = 0;
    var attentionOnly = 0;
    for (final receipt in legacyById.values) {
      if (attentionById.containsKey(receipt.id)) continue;
      legacyOnly += 1;
      if (receipt.suppressionClass == 'noisy' &&
          receipt.inAppPreferenceClass != null) {
        mute += 1;
      } else if (receipt.accessPolicy != 'legacy') {
        authorization += 1;
      } else {
        unexplained += 1;
      }
    }
    for (final receipt in attentionById.values) {
      if (legacyById.containsKey(receipt.id)) continue;
      attentionOnly += 1;
      if (receipt.sourceEventKey != null) {
        newClass += 1;
      } else {
        unexplained += 1;
      }
    }
    return AttentionShadowResult(
      authorization: authorization,
      newClass: newClass,
      mute: mute,
      unexplained: unexplained,
      readAxisMismatch: readAxisMismatch,
      legacyOnly: legacyOnly,
      attentionOnly: attentionOnly,
    );
  }
}

final class AttentionShadowResult {
  const AttentionShadowResult({
    required this.authorization,
    required this.newClass,
    required this.mute,
    required this.unexplained,
    required this.readAxisMismatch,
    required this.legacyOnly,
    required this.attentionOnly,
  });

  final int authorization;
  final int newClass;
  final int mute;
  final int unexplained;
  final int readAxisMismatch;
  final int legacyOnly;
  final int attentionOnly;

  int get expectedTotal => authorization + newClass + mute;
}
