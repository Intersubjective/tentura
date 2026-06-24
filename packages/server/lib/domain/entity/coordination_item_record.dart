import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_server/domain/coordination_stale_rules.dart';
import 'package:tentura_server/utils/id.dart';

part 'coordination_item_record.freezed.dart';

@freezed
abstract class CoordinationItemRecord with _$CoordinationItemRecord {
  static String get newId => generateId('I');

  const factory CoordinationItemRecord({
    required String id,
    required String beaconId,
    required int kind,
    required int status,
    @Default('') String title,
    @Default('') String body,
    required String creatorId,
    String? targetPersonId,
    String? acceptedById,
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
    String? linkedParentItemId,
    @Default(0) int ordering,
    @Default(0) int source,
    @Default(true) bool published,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? publishedAt,
    DateTime? resolvedAt,
    DateTime? cancelledAt,
    DateTime? staleAt,
    DateTime? lastRemindedAt,
    int? staleAfterDays,
  }) = _CoordinationItemRecord;

  const CoordinationItemRecord._();

  CoordinationStaleItemView get staleView => CoordinationStaleItemView(
        kind: kind,
        status: status,
        creatorId: creatorId,
        targetPersonId: targetPersonId,
        acceptedById: acceptedById,
        staleAt: staleAt,
        staleAfterDays: staleAfterDays,
      );
}

/// Domain id factory alias kept for repository call sites.
abstract final class CoordinationItemEntity {
  static String get newId => CoordinationItemRecord.newId;
}
