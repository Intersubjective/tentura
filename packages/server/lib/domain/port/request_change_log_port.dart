/// #528 — who changed what on a Request, told in its discussion.
///
/// The one writer for Request **edit** lines (next step, title). Together
/// with the status line (`BeaconRepositoryPort.recordBeaconStatusTransition`)
/// and the leave line (`BeaconRoomRepositoryPort.recordParticipantLeft`) it
/// follows one pattern: a General system line every member sees, plus the
/// paired `beacon_activity_event` (linked by `source_message_id`) for the
/// Request's log. Who must also be *told* is the producer's attention
/// intent, recorded in the same unit of work. See
/// `docs/features/request-change-events.md`.
// ignore: one_member_abstracts -- injectable port with a single writer
abstract interface class RequestChangeLogPort {
  /// Records that [actorId] changed [field] (`RequestEditField`) of the
  /// Request [beaconId] from [from] to [to]. Runs inside the caller's unit
  /// of work. A Post or an unchanged value writes nothing.
  ///
  /// A run of edits coalesces: when the newest General message is still this
  /// person's line for the same field and younger than
  /// `kRequestEditLineCoalesceWindow`, that line takes the new value (and
  /// moves to now) instead of a second line being added. The activity log
  /// keeps every edit.
  Future<void> recordEdit({
    required String beaconId,
    required String actorId,
    required String field,
    required String from,
    required String to,
  });
}
