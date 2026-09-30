/// Outbox writes of the two hourly closure reminder sweeps (Arch §9). Both
/// methods are idempotent per source event key and join the ambient
/// transaction; each returns the number of rows written.
abstract interface class ClosureReminderSweepPort {
  /// Epochs with `status = 0` closing 23–24 h after [now]: one row per voter
  /// whose draft differs from what they committed (or who has a draft and no
  /// commit). Key `closure_draft_reminder:<beacon>:<epoch>:<voter>`.
  Future<int> writeDraftReminders({required DateTime now});

  /// Open-family requests past their end or silent for 14 days: one row for
  /// the author. Key `stale_request:<beacon>:<[weekKey]>`.
  Future<int> writeStaleRequestReminders({
    required DateTime now,
    required String weekKey,
  });
}
