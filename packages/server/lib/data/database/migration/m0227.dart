part of '_migrations.dart';

/// Price visibility probes so correlated reads do not hash all beacons (#229).
///
/// Per-call measurements in
/// `docs/plans/issue-235-constellation-interactive-measurements.md`,
/// "Per-unit SQL costs", report 0.25–0.36 ms for beacon readability (about
/// 1 ms on dev) and 0.8–6.4 ms for symmetric peer discovery. Use COST 1000
/// for readability and 20000 for peer discovery, conservatively reflecting
/// the latter's roughly twenty-fold upper-bound cost. PostgreSQL COST is a
/// relative weight in cpu_operator_cost units, not a duration in milliseconds.
///
/// The remaining weights estimate their cheaper warm paths: COST 500 for
/// the transaction memo and both mutual-visibility wrappers, which perform
/// memo/index probes, and COST 100 for the indexed symmetric block lookup.
/// These estimates deliberately avoid pricing a scalar readability probe as
/// cheaply as the block lookup (the previous default COST 100 for all six).
final m0227 = Migration('0227', [
  'ALTER FUNCTION public.beacon_can_read_content(text, text) COST 1000',
  'ALTER FUNCTION public.person_visible_peers_symmetric(text, text) COST 20000',
  'ALTER FUNCTION public.person_visible_peer_ids_tx(text, text) COST 500',
  'ALTER FUNCTION public.person_are_mutually_visible(text, text, text) COST 500',
  'ALTER FUNCTION public.person_are_mutually_visible_cached(text, text, text) COST 500',
  'ALTER FUNCTION public.block_hides(text, text) COST 100',
]);
