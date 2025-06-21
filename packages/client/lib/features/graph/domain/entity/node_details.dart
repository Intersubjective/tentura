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
    this.posHint,
  });

  NodeDetails copyWithPosHint(int posHint);

  @override
  NodeDetails copyWithPinned(bool pinned);

  final int? posHint;

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
      posHint.hashCode;

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
          posHint == other.posHint;
}

final class UserNode extends NodeDetails {
  const UserNode({
    required this.user,
    super.pinned,
    super.size,
    super.posHint,
  });

  final Profile user;

  @override
  String get userId => user.id;

  @override
  String get id => user.id;

  @override
  String get label => user.title;

  @override
  bool get hasImage => user.hasAvatar;

  @override
  double get score => user.score;

  @override
  double get rScore => user.rScore;

  @override
  UserNode copyWithPinned(bool pinned) => UserNode(
    pinned: pinned,
    size: size,
    user: user,
    posHint: posHint,
  );

  @override
  UserNode copyWithPosHint(int posHint) => UserNode(
    user: user,
    pinned: pinned,
    size: size,
    posHint: posHint,
  );
}

final class BeaconNode extends NodeDetails {
  const BeaconNode({
    required this.beacon,
    super.pinned,
    super.size,
    super.posHint,
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
  BeaconNode copyWithPinned(bool pinned) => BeaconNode(
    beacon: beacon,
    pinned: pinned,
    size: size,
    posHint: posHint,
  );

  @override
  BeaconNode copyWithPosHint(int posHint) => BeaconNode(
    beacon: beacon,
    pinned: pinned,
    size: size,
    posHint: posHint,
  );
}
