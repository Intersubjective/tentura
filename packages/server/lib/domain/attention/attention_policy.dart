import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';

/// Recipient-specific projection policy. Every output is persisted so reads do
/// not reconstruct event-time role or relationship state.
class AttentionPolicy {
  const AttentionPolicy();

  AttentionReceiptProjection project({
    required AttentionEventType eventType,
    required String recipientId,
    required Set<AttentionRecipientReason> recipientReasons,
    required AttentionRecipientRoleFacts role,
  }) {
    if (recipientId.isEmpty || recipientReasons.isEmpty) {
      throw ArgumentError('recipientId and recipientReasons must be non-empty');
    }

    final suppression = _suppression(eventType, recipientReasons);
    final accessPolicy = _accessPolicy(eventType, role);
    final destination = _destination(eventType, role, accessPolicy);
    final preference = suppression == AttentionSuppressionClass.noisy
        ? _preferenceClass(eventType)
        : null;
    final requiresAction = _requiresAction(eventType, recipientReasons);

    return AttentionReceiptProjection(
      category: _category(eventType, suppression),
      suppressionClass: suppression,
      inAppPreferenceClass: preference,
      accessPolicy: accessPolicy,
      destination: destination,
      presentationKey: _presentationKey(eventType),
      presentationPayload: _presentationPayload(eventType, role),
      requiresAction: requiresAction,
      attentionThreadKey: requiresAction
          ? _threadKey(eventType, recipientId, role)
          : null,
    );
  }

  AttentionSuppressionClass _suppression(
    AttentionEventType eventType,
    Set<AttentionRecipientReason> reasons,
  ) => switch (eventType) {
    AttentionEventType.helpOfferSubmitted =>
      reasons.contains(AttentionRecipientReason.authorOfBeacon)
          ? AttentionSuppressionClass.mandatory
          : AttentionSuppressionClass.standard,
    AttentionEventType.offerAccepted ||
    AttentionEventType.offerDeclined ||
    AttentionEventType.offerRemoved ||
    AttentionEventType.reviewOpened ||
    AttentionEventType.needsMe ||
    AttentionEventType.staleReminder => AttentionSuppressionClass.mandatory,
    AttentionEventType.blockerOpened =>
      reasons.contains(AttentionRecipientReason.affectedParticipant) ||
              reasons.contains(AttentionRecipientReason.targetOfAsk)
          ? AttentionSuppressionClass.mandatory
          : AttentionSuppressionClass.standard,
    AttentionEventType.requestStatusChanged =>
      reasons.any(_isActiveRequestParticipant)
          ? AttentionSuppressionClass.standard
          : AttentionSuppressionClass.noisy,
    AttentionEventType.coordinationChanged => AttentionSuppressionClass.noisy,
    AttentionEventType.relayReceived ||
    AttentionEventType.roomMessagePosted ||
    AttentionEventType.mutualConnectionFormed ||
    AttentionEventType.inviteAccepted ||
    AttentionEventType.blockerResolved ||
    AttentionEventType.promiseMade ||
    AttentionEventType.promiseWithdrawn => AttentionSuppressionClass.standard,
  };

  bool _isActiveRequestParticipant(AttentionRecipientReason reason) =>
      reason == AttentionRecipientReason.authorOfBeacon ||
      reason == AttentionRecipientReason.activeParticipant ||
      reason == AttentionRecipientReason.affectedParticipant ||
      reason == AttentionRecipientReason.admittedRoomMember ||
      reason == AttentionRecipientReason.roomModeratorOrSteward;

  NotificationCategory _category(
    AttentionEventType eventType,
    AttentionSuppressionClass suppression,
  ) => switch (eventType) {
    AttentionEventType.helpOfferSubmitted ||
    AttentionEventType.offerAccepted ||
    AttentionEventType.offerDeclined ||
    AttentionEventType.offerRemoved ||
    AttentionEventType.needsMe ||
    AttentionEventType.staleReminder => NotificationCategory.asksOfMe,
    AttentionEventType.reviewOpened ||
    AttentionEventType.blockerResolved => NotificationCategory.unblocksMe,
    AttentionEventType.mutualConnectionFormed ||
    AttentionEventType.inviteAccepted => NotificationCategory.connections,
    AttentionEventType.relayReceived ||
    AttentionEventType.roomMessagePosted ||
    AttentionEventType.requestStatusChanged ||
    AttentionEventType.blockerOpened ||
    AttentionEventType.promiseMade ||
    AttentionEventType.promiseWithdrawn ||
    AttentionEventType.coordinationChanged => NotificationCategory.coordination,
  };

  AttentionAccessPolicy _accessPolicy(
    AttentionEventType eventType,
    AttentionRecipientRoleFacts role,
  ) => switch (eventType) {
    AttentionEventType.offerDeclined || AttentionEventType.offerRemoved =>
      role.canReadBeaconContent
          ? AttentionAccessPolicy.beaconContent
          : AttentionAccessPolicy.recipientSafe,
    AttentionEventType.mutualConnectionFormed ||
    AttentionEventType.inviteAccepted => AttentionAccessPolicy.profile,
    AttentionEventType.relayReceived ||
    AttentionEventType.helpOfferSubmitted ||
    AttentionEventType.offerAccepted ||
    AttentionEventType.roomMessagePosted ||
    AttentionEventType.requestStatusChanged ||
    AttentionEventType.reviewOpened ||
    AttentionEventType.needsMe ||
    AttentionEventType.blockerOpened ||
    AttentionEventType.blockerResolved ||
    AttentionEventType.promiseMade ||
    AttentionEventType.promiseWithdrawn ||
    AttentionEventType.coordinationChanged ||
    AttentionEventType.staleReminder => AttentionAccessPolicy.beaconContent,
  };

  AttentionDestination _destination(
    AttentionEventType eventType,
    AttentionRecipientRoleFacts role,
    AttentionAccessPolicy accessPolicy,
  ) {
    if (accessPolicy == AttentionAccessPolicy.recipientSafe) {
      return AttentionDestination(
        kind: AttentionDestinationKind.safeTerminal,
        targetEntityId: role.targetEntityId ?? role.beaconId,
      );
    }
    return switch (eventType) {
      AttentionEventType.relayReceived ||
      AttentionEventType.requestStatusChanged => AttentionDestination(
        kind: AttentionDestinationKind.beacon,
        targetEntityId: role.beaconId,
      ),
      AttentionEventType.helpOfferSubmitted ||
      AttentionEventType.offerDeclined ||
      AttentionEventType.offerRemoved => AttentionDestination(
        kind: AttentionDestinationKind.beaconPeopleOffer,
        targetEntityId: role.targetEntityId,
      ),
      AttentionEventType.offerAccepted ||
      AttentionEventType.needsMe ||
      AttentionEventType.blockerOpened ||
      AttentionEventType.blockerResolved ||
      AttentionEventType.promiseMade ||
      AttentionEventType.promiseWithdrawn ||
      AttentionEventType.coordinationChanged ||
      AttentionEventType.staleReminder => AttentionDestination(
        kind: AttentionDestinationKind.beaconRoom,
        targetEntityId: role.coordinationItemId,
      ),
      AttentionEventType.roomMessagePosted => AttentionDestination(
        kind: AttentionDestinationKind.beaconRoomMessage,
        targetEntityId: role.messageId,
      ),
      AttentionEventType.reviewOpened => AttentionDestination(
        kind: AttentionDestinationKind.review,
        targetEntityId: role.beaconId,
      ),
      AttentionEventType.mutualConnectionFormed ||
      AttentionEventType.inviteAccepted => AttentionDestination(
        kind: AttentionDestinationKind.profile,
        targetEntityId: role.targetEntityId,
      ),
    };
  }

  AttentionPreferenceClass? _preferenceClass(AttentionEventType eventType) =>
      switch (eventType) {
        AttentionEventType.coordinationChanged =>
          AttentionPreferenceClass.coordinationChurn,
        AttentionEventType.requestStatusChanged =>
          AttentionPreferenceClass.requestProgress,
        _ => null,
      };

  bool _requiresAction(
    AttentionEventType eventType,
    Set<AttentionRecipientReason> reasons,
  ) => switch (eventType) {
    AttentionEventType.helpOfferSubmitted => reasons.contains(
      AttentionRecipientReason.authorOfBeacon,
    ),
    AttentionEventType.needsMe ||
    AttentionEventType.staleReminder ||
    AttentionEventType.reviewOpened => true,
    AttentionEventType.blockerOpened =>
      reasons.contains(AttentionRecipientReason.affectedParticipant) ||
          reasons.contains(AttentionRecipientReason.targetOfAsk),
    _ => false,
  };

  String _threadKey(
    AttentionEventType eventType,
    String recipientId,
    AttentionRecipientRoleFacts role,
  ) {
    final subject =
        role.coordinationItemId ?? role.targetEntityId ?? role.beaconId;
    if (subject == null || subject.isEmpty) {
      throw ArgumentError('Live obligation requires a stable subject');
    }
    return [
      'v1',
      eventType.name,
      Uri.encodeComponent(subject),
      Uri.encodeComponent(recipientId),
    ].join('|');
  }

  String _presentationKey(AttentionEventType eventType) => switch (eventType) {
    AttentionEventType.relayReceived => 'relay_received',
    AttentionEventType.helpOfferSubmitted => 'help_offer_submitted',
    AttentionEventType.offerAccepted => 'offer_accepted',
    AttentionEventType.offerDeclined => 'offer_declined',
    AttentionEventType.offerRemoved => 'offer_removed',
    AttentionEventType.roomMessagePosted => 'room_message_posted',
    AttentionEventType.requestStatusChanged => 'request_status_changed',
    AttentionEventType.reviewOpened => 'review_opened',
    AttentionEventType.mutualConnectionFormed => 'mutual_connection_formed',
    AttentionEventType.inviteAccepted => 'invite_accepted',
    AttentionEventType.needsMe => 'needs_me',
    AttentionEventType.blockerOpened => 'blocker_opened',
    AttentionEventType.blockerResolved => 'blocker_resolved',
    AttentionEventType.promiseMade => 'promise_made',
    AttentionEventType.promiseWithdrawn => 'promise_withdrawn',
    AttentionEventType.coordinationChanged => 'coordination_changed',
    AttentionEventType.staleReminder => 'stale_reminder',
  };

  Map<String, Object?> _presentationPayload(
    AttentionEventType eventType,
    AttentionRecipientRoleFacts role,
  ) {
    final payload = <String, Object?>{'eventType': eventType.name};
    final values = <String, String?>{
      'actorUserId': _safeId(role.actorUserId),
      'beaconId': _safeId(role.beaconId),
      'coordinationItemId': _safeId(role.coordinationItemId),
      'targetEntityId': _safeId(role.targetEntityId),
      'messageId': _safeId(role.messageId),
    };
    for (final MapEntry(:key, :value) in values.entries) {
      if (value != null) {
        payload[key] = value;
      }
    }
    return payload;
  }

  String? _safeId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed.length > 256) {
      return null;
    }
    return trimmed;
  }
}
