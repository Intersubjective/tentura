import 'package:meta/meta.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';

import '../entity/constellation_field.dart';

/// Glyph drawn for a Beacon node on the Constellation field map.
enum FieldBeaconGlyph { request, post }

/// Pure description of one Request or Post satellite emitted by composition.
/// The scene side maps it to its own node type.
@immutable
class LayoutNodeSpec {
  const LayoutNodeSpec({
    this.request,
    this.post,
    this.pinned = false,
  }) : assert(
         (request == null) != (post == null),
         'exactly one of request / post',
       );

  final ConstellationRequest? request;
  final ConstellationPost? post;
  final bool pinned;

  String get id => post?.id ?? request!.id;

  String get authorId => post?.authorId ?? request!.authorId;

  String get label => post?.rootExcerpt ?? request!.title;

  BeaconKind get kind => post == null ? BeaconKind.request : BeaconKind.post;

  FieldBeaconGlyph get glyph =>
      post == null ? FieldBeaconGlyph.request : FieldBeaconGlyph.post;

  /// Posts carry no lifecycle status.
  bool get hasStatusMarker => post == null;
}
