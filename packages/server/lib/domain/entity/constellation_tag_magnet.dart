import 'package:meta/meta.dart';

/// A viewer's magnet for one of their own tags on the Field: where people with
/// that tag drift towards. [revision] counts the magnet's moves.
@immutable
final class ConstellationTagMagnet {
  const ConstellationTagMagnet({
    required this.tagId,
    required this.xUnits,
    required this.yUnits,
    required this.revision,
  });

  factory ConstellationTagMagnet.fromJson(Map<String, dynamic> json) =>
      ConstellationTagMagnet(
        tagId: json['tagId']! as String,
        xUnits: (json['xUnits']! as num).toDouble(),
        yUnits: (json['yUnits']! as num).toDouble(),
        revision: json['revision']! as int,
      );

  final String tagId;
  final double xUnits;
  final double yUnits;
  final int revision;

  /// Also the GraphQL `ConstellationTagMagnet` object.
  Map<String, dynamic> toJson() => {
    'tagId': tagId,
    'xUnits': xUnits,
    'yUnits': yUnits,
    'revision': revision,
  };

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
