/// Realtime entity kinds that always fan out to the actor's own sessions
/// regardless of [Env.realtimeActorEchoEnabled] (C8 private invalidation).
const kRealtimeAlwaysEchoKinds = {'constellation_anchor'};
