/// Realtime entity kinds that always fan out to the actor's own sessions
/// regardless of [Env.realtimeActorEchoEnabled] (C8 private invalidation).
/// `room_seen` is the reader's own cursor: its other sessions must converge.
/// Field-open hints likewise converge the reader's own Field in every session.
const kRealtimeAlwaysEchoKinds = {
  'constellation_anchor',
  'person_tag',
  'room_seen',
  'constellation_field',
};
