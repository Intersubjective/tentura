import 'package:meta/meta.dart';

import 'constellation_field_target_kind.dart';

enum ConstellationPersonFieldBucket {
  active,
  closed,
  hidden;

  String get wireValue => switch (this) {
    ConstellationPersonFieldBucket.active => 'active',
    ConstellationPersonFieldBucket.closed => 'closed',
    ConstellationPersonFieldBucket.hidden => 'hidden',
  };

  static ConstellationPersonFieldBucket fromWire(String value) =>
      switch (value) {
        'active' => ConstellationPersonFieldBucket.active,
        'closed' => ConstellationPersonFieldBucket.closed,
        'hidden' => ConstellationPersonFieldBucket.hidden,
        _ => throw ArgumentError.value(value, 'bucket'),
      };
}

@immutable
final class ConstellationPersonFieldItem {
  const ConstellationPersonFieldItem({
    required this.id,
    required this.kind,
    required this.authorId,
    required this.title,
    required this.rootExcerpt,
    required this.status,
    required this.hidden,
    required this.lastActivityAt,
    this.expiresAt,
  });

  final String id;
  final ConstellationFieldTargetKind kind;
  final String authorId;
  final String title;
  final String rootExcerpt;
  final int status;
  final bool hidden;
  final DateTime lastActivityAt;
  final DateTime? expiresAt;

  String get label =>
      kind == ConstellationFieldTargetKind.post ? rootExcerpt : title;
}

@immutable
final class ConstellationPersonFieldCounts {
  const ConstellationPersonFieldCounts({
    required this.active,
    required this.closed,
    required this.hidden,
  });

  final int active;
  final int closed;
  final int hidden;
}

@immutable
final class ConstellationPersonFieldItemsPage {
  const ConstellationPersonFieldItemsPage({
    this.items = const [],
    this.nextCursor,
    this.counts = const ConstellationPersonFieldCounts(
      active: 0,
      closed: 0,
      hidden: 0,
    ),
  });

  final List<ConstellationPersonFieldItem> items;
  final String? nextCursor;
  final ConstellationPersonFieldCounts counts;
}

const emptyConstellationPersonFieldItemsPage =
    ConstellationPersonFieldItemsPage();
