import 'package:flutter/foundation.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart'
    show NodeBase;

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';

@immutable
sealed class NodeDetails extends NodeBase {
  const NodeDetails({
    super.size = 40,
    super.pinned,
    this.positionHint,
  });

  final int? positionHint;

  NodeDetails copyWithPositionHint(int? positionHint);

  @override
  NodeDetails copyWithPinned(bool isPinned);

  String get id;

  String get userId;

  String get label;

  bool get hasImage;

  double get rScore;

  double get score;

  @override
  int get hashCode =>
      id.hashCode ^
      label.hashCode ^
      score.hashCode ^
      userId.hashCode ^
      hasImage.hashCode ^
      positionHint.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeDetails &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          score == other.score &&
          userId == other.userId &&
          hasImage == other.hasImage &&
          positionHint == other.positionHint;
}

final class UserNode extends NodeDetails {
  const UserNode({
    required this.user,
    super.pinned,
    super.size,
    super.positionHint,
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
    positionHint: positionHint,
    isHelpOfferer: isHelpOfferer,
  );

  @override
  UserNode copyWithPositionHint(int? positionHint) => UserNode(
    user: user,
    size: size,
    pinned: pinned,
    positionHint: positionHint,
    isHelpOfferer: isHelpOfferer,
  );

  UserNode copyWithIsHelpOfferer(bool value) => UserNode(
    user: user,
    size: size,
    pinned: pinned,
    positionHint: positionHint,
    isHelpOfferer: value,
  );

  @override
  int get hashCode => super.hashCode ^ isHelpOfferer.hashCode;

  @override
  bool operator ==(Object other) =>
      super == other && other is UserNode && other.isHelpOfferer == isHelpOfferer;
}

final class BeaconNode extends NodeDetails {
  const BeaconNode({
    required this.beacon,
    super.positionHint,
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
    positionHint: positionHint,
    size: size,
  );

  @override
  BeaconNode copyWithPositionHint(int? positionHint) => BeaconNode(
    beacon: beacon,
    pinned: pinned,
    positionHint: positionHint,
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
    super.positionHint,
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
    positionHint: positionHint,
  );

  @override
  GenealogyUserNode copyWithPositionHint(int? positionHint) =>
      GenealogyUserNode(
        nodeKey: nodeKey,
        user: user,
        pinned: pinned,
        size: size,
        positionHint: positionHint,
      );
}

/// Anonymized endpoint after account deletion.
final class GenealogyDeletedNode extends NodeDetails {
  const GenealogyDeletedNode({
    required this.nodeKey,
    required this.label,
    super.pinned,
    super.size,
    super.positionHint,
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
    positionHint: positionHint,
  );

  @override
  GenealogyDeletedNode copyWithPositionHint(int? positionHint) =>
      GenealogyDeletedNode(
        nodeKey: nodeKey,
        label: label,
        pinned: pinned,
        size: size,
        positionHint: positionHint,
      );
}
