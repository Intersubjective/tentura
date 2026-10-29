import 'dart:async';

import 'package:fake_async/fake_async.dart';

/// The cast of one replay. The author owns a published root Request; the
/// helpers are admitted (room access granted). No plan steps are assigned, no
/// invites are pending, no obligation is live and no child changes.
const kReplayAuthorId = 'author';
const kReplayHelperId = 'helper';
const kReplayOtherHelperId = 'another-helper';

/// One `pg_notify('entity_changes', …)` envelope as the server emits it:
/// `entity`, `id`, `event`, `user_ids` and optional `message_id`.
typedef ServerHint = ({
  String entity,
  String id,
  String event,
  List<String> userIds,
  String? messageId,
});

/// One server change, as the hints its single mutation transaction emits.
///
/// Every hint below is taken from the server emit path (paths relative to
/// packages/server/lib/data/database/migration unless noted):
/// * Envelope ids (m0193 notify_entity_change): `beacon` uses the beacon row
///   id; `help_offer`, `room_message`, `participant`, `activity_event` and
///   `inbox_item` use the row's beacon_id; `room_message` adds the row id as
///   `message_id`; `notification` (notify_notification_outbox_insert) uses
///   the receipt's account_id. `beacon_hierarchy`
///   (realtime_beacon_hierarchy_emit) uses the projection owner, which for a
///   root Request is the Request itself.
/// * Recipients: realtime_beacon_recipients = author, every participant row
///   and active offers; realtime_room_recipients = author and admitted
///   participants; m0243 realtime_beacon_hierarchy_recipients = owner and
///   admitted participants. `help_offer` and `participant` add the row's
///   user, `room_message` adds its author, `inbox_item` and `notification`
///   go to their own user only.
/// * Enough help (packages/server/lib/domain/use_case/coordination_case.dart
///   setBeaconStatus): one beacon update (+ its hierarchy hint), one
///   activity event and one status system line; open-family status writes no
///   inbox rows; one notification receipt for the non-actor helper.
/// * Helper leaves (packages/server/lib/domain/use_case/help_offer_case.dart
///   withdraw): help_offer update, participant-left line, its activity
///   event, participant revoke (+ m0193 admission hierarchy hint), the
///   leaver's own watching inbox row, the author's helpWithdrawn receipt.
/// * Delivery: pg_notify fires after commit, in emit order, with no
///   transaction id. The server fan-out (packages/server/lib/api/controllers/
///   websocket/path_handler/websocket_path_entity_changes.dart) sends a hint
///   only to sessions whose user is in `user_ids`, strips `user_ids`, and
///   echoes to the actor unless REALTIME_ACTOR_ECHO_ENABLED=false.
enum RequestChangeReplay {
  /// The author sets Enough help (later: Needs more help); the helper watches.
  enoughHelp,

  /// A helper withdraws; the author watches. Generation 1 is [kReplayHelperId]
  /// leaving, generation 2 is [kReplayOtherHelperId] leaving.
  helperLeaves;

  /// The account whose open client is measured.
  String get viewerId => this == enoughHelp ? kReplayHelperId : kReplayAuthorId;

  /// Who made change [generation].
  String actorFor(int generation) => switch (this) {
    enoughHelp => kReplayAuthorId,
    helperLeaves => generation == 1 ? kReplayHelperId : kReplayOtherHelperId,
  };

  /// Every hint change [generation] makes the server emit, for any recipient.
  List<ServerHint> serverHints({
    required String beaconId,
    required int generation,
  }) {
    ServerHint hint(
      String entity,
      String event,
      Iterable<String> userIds, {
      String? id,
      String? messageId,
    }) => (
      entity: entity,
      id: id ?? beaconId,
      event: event,
      userIds: userIds.toSet().toList(),
      messageId: messageId,
    );
    final messageId = 'notice-$generation';
    switch (this) {
      case enoughHelp:
        const everyone = [kReplayAuthorId, kReplayHelperId];
        return [
          hint('beacon', 'update', everyone),
          hint('beacon_hierarchy', 'update', everyone),
          hint('activity_event', 'insert', everyone),
          hint('room_message', 'insert', everyone, messageId: messageId),
          hint(
            'notification',
            'insert',
            const [kReplayHelperId],
            id: kReplayHelperId,
          ),
        ];
      case helperLeaves:
        final leaver = actorFor(generation);
        // Generation 2: the first helper already left and lost room access,
        // but still has a participant row (beacon recipients).
        final beaconParticipants = [
          kReplayAuthorId,
          kReplayHelperId,
          kReplayOtherHelperId,
        ];
        final admittedBefore = [
          kReplayAuthorId,
          if (generation == 1) kReplayHelperId,
          kReplayOtherHelperId,
        ];
        final admittedAfter = [
          for (final id in admittedBefore)
            if (id != leaver) id,
        ];
        return [
          hint('help_offer', 'update', [...beaconParticipants, leaver]),
          hint(
            'room_message',
            'insert',
            [...admittedBefore, leaver],
            messageId: messageId,
          ),
          hint('activity_event', 'insert', beaconParticipants),
          hint('participant', 'update', [...admittedAfter, leaver]),
          hint('beacon_hierarchy', 'update', [...admittedAfter, leaver]),
          hint('inbox_item', 'update', [leaver]),
          hint(
            'notification',
            'insert',
            const [kReplayAuthorId],
            id: kReplayAuthorId,
          ),
        ];
    }
  }

  /// The wire frames the viewer's socket receives, in emit order, after the
  /// server fan-out (recipient filter, actor echo on by default).
  List<Map<String, dynamic>> viewerFrames({
    required String beaconId,
    required int generation,
  }) => [
    for (final hint in serverHints(beaconId: beaconId, generation: generation))
      if (hint.userIds.contains(viewerId))
        {
          'type': 'subscription',
          'path': 'entity_changes',
          'payload': {
            'entity': hint.entity,
            'id': hint.id,
            'event': hint.event,
            'actor_user_id': actorFor(generation),
            // Thin room hint: the paint snapshot is optional on the wire.
            if (hint.messageId != null) 'message_id': hint.messageId,
          },
        },
  ];

  /// The spread one change's hints reach an open client over (QA: ~2 s).
  static const burstSpread = Duration(seconds: 2);

  /// The 100 ms entity-change buffer of InvalidationService (16 ms for room
  /// messages). Hints further apart than this land in separate flushes.
  static const invalidationBuffer = Duration(milliseconds: 100);

  /// Delivers change [generation] to [socket] as a delivery envelope, NOT a
  /// captured trace: the report gives the ~2 s spread but no per-frame
  /// timestamps, and the server sends one commit's frames back to back. The
  /// frames keep their real ids, recipients and emit order and are spaced
  /// evenly over [burstSpread]; every gap exceeds [invalidationBuffer], so
  /// each hint reaches the app in its own InvalidationService flush.
  void deliver({
    required FakeAsync clock,
    required StreamController<Map<String, dynamic>> socket,
    required String beaconId,
    required int generation,
  }) {
    final frames = viewerFrames(beaconId: beaconId, generation: generation);
    final gap = burstSpread ~/ (frames.length - 1);
    assert(gap > invalidationBuffer, 'frames must not share a flush');
    for (final (index, frame) in frames.indexed) {
      if (index > 0) clock.elapse(gap);
      socket.add(frame);
      clock.flushMicrotasks();
    }
  }
}
