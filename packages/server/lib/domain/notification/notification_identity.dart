import 'package:meta/meta.dart';

enum NotificationEntityKind { request, post }

/// One entity request for [NotificationIdentityPort.resolve].
class IdentityRequest {
  const IdentityRequest({
    required this.beaconId,
    this.actorId,
    this.relatedBeaconId,
  });

  final String beaconId;
  final String? actorId;
  final String? relatedBeaconId;
}

/// What a recipient may see of an entity and an actor, access-gated.
/// Labels are raw (normalized and truncated); localized copy is rendered later.
@immutable
class NotificationIdentity {
  const NotificationIdentity({
    required this.entityKind,
    required this.label,
    required this.tombstone,
    required this.readable,
    required this.actorName,
    required this.actorHidden,
    required this.relatedLabel,
    required this.expired,
    this.hasImage = false,
    this.deleted = false,
    this.authorName,
    this.isPostBud = false,
  });

  final NotificationEntityKind entityKind;
  final String? label;
  final bool tombstone;
  final bool readable;
  final String? actorName;
  final bool actorHidden;
  final String? relatedLabel;
  final bool expired;
  final bool hasImage;

  /// The entity is deleted (status 2), whether or not [tombstone] is
  /// readable.
  final bool deleted;

  /// The Post author's live name, set only for a readable Post.
  final String? authorName;

  final bool isPostBud;

  /// Even generic copy or a deep link would disclose an unreadable bud, but a
  /// viewer who may see the tombstone still gets the «deleted» notice.
  bool get hidesNotification => isPostBud && !readable && !tombstone;

  @override
  bool operator ==(Object other) =>
      other is NotificationIdentity &&
      other.entityKind == entityKind &&
      other.label == label &&
      other.tombstone == tombstone &&
      other.readable == readable &&
      other.actorName == actorName &&
      other.actorHidden == actorHidden &&
      other.relatedLabel == relatedLabel &&
      other.expired == expired &&
      other.hasImage == hasImage &&
      other.deleted == deleted &&
      other.authorName == authorName &&
      other.isPostBud == isPostBud;

  @override
  int get hashCode => Object.hash(
    entityKind,
    label,
    tombstone,
    readable,
    actorName,
    actorHidden,
    relatedLabel,
    expired,
    hasImage,
    deleted,
    authorName,
    isPostBud,
  );
}

abstract class NotificationIdentityPort {
  /// One identity per request, in request order, for [recipientId].
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> requests,
  );
}
