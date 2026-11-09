import 'package:tentura_server/domain/port/witness_window_port.dart';

/// Drops the cached witness windows of both users of a pair whose trust
/// relation just changed (a vote, a block, an unblock, a released cascade
/// row): [firstUserId] first, then [secondUserId].
///
/// The one implementation of the rule: the block and trust-edge use cases
/// and the block repository (cascade pairs, released rows) all call it.
/// A null [witnessWindow] (no cache wired) is a no-op.
Future<void> invalidateWitnessWindowsForPair(
  WitnessWindowPort? witnessWindow,
  String firstUserId,
  String secondUserId,
) async {
  if (witnessWindow == null) return;
  await witnessWindow.invalidateFor(userId: firstUserId);
  await witnessWindow.invalidateFor(userId: secondUserId);
}
