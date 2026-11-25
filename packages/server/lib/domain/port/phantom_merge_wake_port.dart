/// Best-effort prompt for the worker to check its durable merge queue.
class PhantomMergeWakePort {
  const PhantomMergeWakePort.disabled();

  /// Call after the accepting transaction commits.
  Future<void> wake(String invitationId) async {}
}
