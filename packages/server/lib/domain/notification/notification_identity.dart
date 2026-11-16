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
      other.hasImage == hasImage;

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
  );
}

abstract class NotificationIdentityPort {
  /// One identity per request, in request order, for [recipientId].
  Future<List<NotificationIdentity>> resolve(
    String recipientId,
    List<IdentityRequest> requests,
  );
}
