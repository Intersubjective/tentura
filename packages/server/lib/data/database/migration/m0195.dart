part of '_migrations.dart';

/// Drops `nested_requests_apply_legacy_cleanup()`, a one-shot helper that has
/// had nothing to do since the migration that ran it.
///
/// `m0158` defined this function and then, as its own last statement, called
/// it: `SELECT public.nested_requests_apply_legacy_cleanup();`. It removed the
/// legacy ask/promise/blocker items and non-General thread messages that
/// predated nested requests, once, inside the transaction that carried a
/// database across `0158`. `m0158` left it defined on purpose — its own comment
/// says it "may be invoked again after a successful run; subsequent passes
/// delete/update zero rows" — but nothing ever has, and both deployments are
/// long since clean of the rows it targets (`docs/plans/migration-squash-plan.md`
/// §10.1).
///
/// The squashed baseline inherited the definition because it is a dump of the
/// schema the chain built, so every new database gets it too. Dropping it here
/// rather than stripping it from `m0193` is deliberate: `m0193` has shipped, and
/// editing a migration that has shipped reaches only the databases that have not
/// yet applied it — which is the fault this session spent its time repairing
/// (§10.2). A later regeneration of the baseline will simply not contain the
/// function, because the database it dumps will have run this migration.
///
/// Nothing references it: no Dart, SQL, Hasura metadata, no other function body,
/// and `pg_depend` reports no dependents on either deployment.
final m0195 = Migration('0195', [
  'DROP FUNCTION IF EXISTS public.nested_requests_apply_legacy_cleanup();',
]);
