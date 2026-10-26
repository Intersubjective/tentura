import 'package:meta/meta.dart';

/// The viewer's magnet for one of their own tags: where people with that tag
/// drift towards on the Field. Positions are in the Field's anchor units.
@immutable
final class ConstellationTagMagnet {
  const ConstellationTagMagnet({
    required this.tagId,
    required this.xUnits,
    required this.yUnits,
    required this.revision,
  });

  final String tagId;
  final double xUnits;
  final double yUnits;

  /// Counts the magnet's moves.
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ConstellationTagMagnet &&
      other.tagId == tagId &&
      other.xUnits == xUnits &&
      other.yUnits == yUnits &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(tagId, xUnits, yUnits, revision);
}
