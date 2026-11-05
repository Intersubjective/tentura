import 'package:meta/meta.dart';

import 'constellation_field_target_kind.dart';

@immutable
final class ConstellationFieldHiddenItem {
  const ConstellationFieldHiddenItem({
    required this.targetKind,
    required this.targetId,
    required this.title,
    required this.authorId,
    required this.hiddenAt,
  });

  final ConstellationFieldTargetKind targetKind;
  final String targetId;
  final String title;
  final String authorId;
  final DateTime hiddenAt;
}
