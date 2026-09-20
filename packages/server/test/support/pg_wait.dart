/// Budgets for tests that wait on another session reaching a known state.
///
/// **The rule.** You cannot observe "another backend is now blocked" without
/// polling; what you can do is make the polled predicate *stable* and then give
/// it room. A predicate is stable when the state it waits for is held until
/// this test releases it — a blocker holding an advisory lock until
/// `releaseBlocker.complete()`, for instance. Such a wait is not a race: it
/// succeeds given enough time, so a short budget buys nothing and converts
/// machine load into false failures.
///
/// A predicate that waits for something *transient* — a state the other session
/// will leave on its own — is a race and cannot be fixed by a longer budget.
/// Restructure it: make the state stable, or assert the outcome instead.
///
/// Both kinds were present here. `capability_evidence_repository_pg_test`
/// polled `pg_locks` unscoped, so another database's schema upgrade satisfied
/// it and the test moved on before its own blocker was in place — which turned
/// its *next*, stable wait into a guaranteed five-second timeout. Scoping the
/// query made the wait honest; this constant stops the honest wait from failing
/// under load.
library;

/// Waiting for a state another session holds until this test releases it.
///
/// Deliberately generous: on a passing run it is never reached, and on a
/// failing one the extra seconds cost far less than a flaky suite does.
const kStableStateWait = Duration(seconds: 30);

/// Waiting for an operation to finish once it has been unblocked.
const kCompletionWait = Duration(seconds: 30);
