import 'package:flutter/foundation.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';

import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

@immutable
sealed class NodeDetails {
  const NodeDetails({
    this.size = 40,
    this.pinned = false,
  });

  final double size;

  final bool pinned;

  NodeDetails copyWithPinned(bool isPinned);

  String get id;

  String get userId;

  String get label;

  /// Scene node id: kind prefix + [id]; stable across payload changes.
  String get graphNodeId => switch (this) {
    UserNode() => 'u:$id',
    BeaconNode() => 'b:$id',
    FieldPersonNode() => 'fp:$id',
    FieldBeaconNode() => 'fr:$id',
    FieldDraftNode() => 'fd:$id',
    GenealogyUserNode() => 'gu:$id',
    GenealogyDeletedNode() => 'gd:$id',
  };

  bool get hasImage;

  double get rScore;

  double get score;

  @override
  int get hashCode =>
      id.hashCode ^
      label.hashCode ^
      score.hashCode ^
      rScore.hashCode ^
      userId.hashCode ^
      hasImage.hashCode ^
      pinned.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeDetails &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          score == other.score &&
          rScore == other.rScore &&
          userId == other.userId &&
          hasImage == other.hasImage &&
          pinned == other.pinned;
}

final class UserNode extends NodeDetails {
  const UserNode({
    required this.user,
    super.pinned,
    super.size,
    this.isHelpOfferer = false,
  });

  final Profile user;

  /// True when the user has an active help offer for the focused beacon
  /// (forwards graph only). Used by the renderer to draw a highlight ring.
  final bool isHelpOfferer;

  @override
  String get userId => user.id;

  @override
  String get id => user.id;

  @override
  String get label => user.shownName;

  @override
  bool get hasImage => user.hasAvatar;

  @override
  double get score => user.score;

  @override
  double get rScore => user.rScore;

  bool get canSeeMe => user.isSeeingMe;

  @override
  UserNode copyWithPinned(bool isPinned) => UserNode(
    size: size,
    user: user,
    pinned: isPinned,
    isHelpOfferer: isHelpOfferer,
  );

  UserNode copyWithIsHelpOfferer(bool value) => UserNode(
    user: user,
    size: size,
    pinned: pinned,
    isHelpOfferer: value,
  );

  @override
  int get hashCode =>
      super.hashCode ^
      isHelpOfferer.hashCode ^
      user.myVote.hashCode ^
      user.subjectExplicitlyTrustsViewer.hashCode ^
      user.isMutualFriend.hashCode;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is UserNode &&
      other.isHelpOfferer == isHelpOfferer &&
      other.user.myVote == user.myVote &&
      other.user.subjectExplicitlyTrustsViewer ==
          user.subjectExplicitlyTrustsViewer &&
      other.user.isMutualFriend == user.isMutualFriend;
}

final class BeaconNode extends NodeDetails {
  const BeaconNode({
    required this.beacon,
    super.pinned,
    super.size,
  });

  final Beacon beacon;

  @override
  String get userId => beacon.author.id;

  @override
  String get id => beacon.id;

  @override
  String get label => beacon.title;

  @override
  bool get hasImage => beacon.hasPicture;

  @override
  double get rScore => beacon.rScore;

  @override
  double get score => beacon.score;

  @override
  BeaconNode copyWithPinned(bool isPinned) => BeaconNode(
    beacon: beacon,
    pinned: isPinned,
    size: size,
  );
}

/// Live user in the invite-genealogy graph. [id] is the opaque [nodeKey], not
/// the account id, so deleted endpoints cannot be reidentified from graph ids.
final class GenealogyUserNode extends NodeDetails {
  const GenealogyUserNode({
    required this.nodeKey,
    required this.user,
    super.pinned,
    super.size,
  });

  final String nodeKey;
  final Profile user;

  @override
  String get userId => user.id;

  @override
  String get id => nodeKey;

  @override
  String get label => user.shownName;

  @override
  bool get hasImage => user.hasAvatar;

  @override
  double get score => user.score;

  @override
  double get rScore => user.rScore;

  @override
  GenealogyUserNode copyWithPinned(bool isPinned) => GenealogyUserNode(
    nodeKey: nodeKey,
    user: user,
    pinned: isPinned,
    size: size,
  );

  @override
  int get hashCode =>
      super.hashCode ^
      user.myVote.hashCode ^
      user.subjectExplicitlyTrustsViewer.hashCode ^
      user.isMutualFriend.hashCode;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is GenealogyUserNode &&
      other.user.myVote == user.myVote &&
      other.user.subjectExplicitlyTrustsViewer ==
          user.subjectExplicitlyTrustsViewer &&
      other.user.isMutualFriend == user.isMutualFriend;
}

/// Anonymized endpoint after account deletion.
final class GenealogyDeletedNode extends NodeDetails {
  const GenealogyDeletedNode({
    required this.nodeKey,
    required this.label,
    super.pinned,
    super.size,
  });

  final String nodeKey;
  @override
  final String label;

  @override
  String get userId => nodeKey;

  @override
  String get id => nodeKey;

  @override
  bool get hasImage => false;

  @override
  double get score => 0;

  @override
  double get rScore => 0;

  @override
  GenealogyDeletedNode copyWithPinned(bool isPinned) => GenealogyDeletedNode(
    nodeKey: nodeKey,
    label: label,
    pinned: isPinned,
    size: size,
  );
}

/// Person node on the Constellation field map.
final class FieldPersonNode extends NodeDetails {
  const FieldPersonNode({
    required this.person,
    required this.ring,
    required this.isKept,
    super.pinned,
    super.size,
  });

  final Profile person;
  final int ring;
  final bool isKept;

  @override
  String get userId => person.id;

  @override
  String get id => person.id;

  @override
  String get label => person.shownName;

  @override
  bool get hasImage => person.hasAvatar;

  @override
  double get score => person.score;

  @override
  double get rScore => person.rScore;

  @override
  FieldPersonNode copyWithPinned(bool isPinned) => FieldPersonNode(
    person: person,
    ring: ring,
    isKept: isKept,
    pinned: isPinned,
    size: size,
  );

  @override
  int get hashCode =>
      super.hashCode ^ ring.hashCode ^ isKept.hashCode ^ person.hashCode;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is FieldPersonNode &&
      other.ring == ring &&
      other.isKept == isKept &&
      other.person == person;
}

/// Glyph drawn for a [FieldBeaconNode].
enum FieldBeaconGlyph { request, post }

/// Request or Post satellite on the Constellation field map.
final class FieldBeaconNode extends NodeDetails {
  const FieldBeaconNode({
    this.request,
    this.post,
    super.pinned,
    super.size = 36,
  }) : assert(
         (request == null) != (post == null),
         'exactly one of request / post',
       );

  final ConstellationRequest? request;
  final ConstellationPost? post;

  BeaconKind get kind => post == null ? BeaconKind.request : BeaconKind.post;

  FieldBeaconGlyph get glyph =>
      post == null ? FieldBeaconGlyph.request : FieldBeaconGlyph.post;

  /// Posts carry no lifecycle status.
  bool get hasStatusMarker => post == null;

  @override
  String get userId => post?.authorId ?? request!.authorId;

  @override
  String get id => post?.id ?? request!.id;

  @override
  String get label => post?.rootExcerpt ?? request!.title;

  @override
  bool get hasImage => request?.coverThumb != null;

  @override
  double get score => 0;

  @override
  double get rScore => 0;

  @override
  FieldBeaconNode copyWithPinned(bool isPinned) => FieldBeaconNode(
    request: request,
    post: post,
    pinned: isPinned,
    size: size,
  );

  @override
  int get hashCode => super.hashCode ^ request.hashCode ^ post.hashCode;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is FieldBeaconNode &&
      other.request == request &&
      other.post == post;
}

/// Draft Post node shown while composing on the Constellation field map.
final class FieldDraftNode extends NodeDetails {
  const FieldDraftNode({super.size = 36});

  static const draftId = 'draft';

  @override
  String get id => draftId;

  @override
  String get userId => '';

  @override
  String get label => '';

  @override
  bool get hasImage => false;

  @override
  double get score => 0;

  @override
  double get rScore => 0;

  @override
  FieldDraftNode copyWithPinned(bool isPinned) => FieldDraftNode(size: size);
}
