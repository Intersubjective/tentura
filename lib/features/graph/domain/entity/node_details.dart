import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart'
    show NodeBase;

@immutable
sealed class NodeDetails extends NodeBase with EquatableMixin {
  const NodeDetails({
    required this.id,
    this.hasImage = false,
    this.label = '',
    this.score = 0,
    super.size = 40,
    super.pinned,
  });

  final String id;
  final String label;
  final double score;
  final bool hasImage;

  @override
  List<Object> get props => [id];

  String get userId;
}

final class UserNode extends NodeDetails {
  const UserNode({
    required super.id,
    super.score,
    super.label,
    super.size,
    super.pinned,
    super.hasImage,
  });

  @override
  String get userId => id;

  @override
  UserNode copyWithPinned(bool pinned) => UserNode(
        id: id,
        size: size,
        label: label,
        hasImage: hasImage,
        pinned: pinned,
        score: score,
      );
}

final class BeaconNode extends NodeDetails {
  const BeaconNode({
    required this.userId,
    required super.id,
    super.score,
    super.label,
    super.size,
    super.pinned,
    super.hasImage,
  });

  @override
  final String userId;

  @override
  BeaconNode copyWithPinned(bool pinned) => BeaconNode(
        id: id,
        size: size,
        label: label,
        userId: userId,
        hasImage: hasImage,
        pinned: pinned,
        score: score,
      );
}

final class CommentNode extends NodeDetails {
  const CommentNode({
    required this.userId,
    required this.beaconId,
    required super.id,
    super.pinned,
    super.score,
    super.size,
  });

  @override
  final String userId;

  final String beaconId;

  @override
  String get label => id;

  @override
  CommentNode copyWithPinned(bool pinned) => CommentNode(
        id: id,
        size: size,
        userId: userId,
        beaconId: beaconId,
        pinned: pinned,
        score: score,
      );
}
