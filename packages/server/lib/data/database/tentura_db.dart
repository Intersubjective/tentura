import 'dart:async';
import 'dart:math' show max;

import 'package:drift/backends.dart'
    show
        DatabaseDelegate,
        DbVersionDelegate,
        DelegatedDatabase,
        NoVersionDelegate,
        QueryDelegate,
        QueryResult,
        SupportedTransactionDelegate,
        TransactionDelegate;
import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/account_session_entity.dart';
import 'package:tentura_server/domain/entity/email_auth_transaction_entity.dart';
import 'package:tentura_server/domain/entity/verified_contact_entity.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_fact_card_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/polling_entity.dart';
import 'package:tentura_server/domain/entity/polling_variant_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

import 'postgres_serialization_retry.dart';
import 'custom_types/mentions_text_array_type.dart';
import 'table/account_credentials.dart';
import 'table/account_verified_contacts.dart';
import 'table/account_sessions.dart';
import 'table/email_auth_transactions.dart';
import 'table/beacon_help_offers.dart';
import 'table/beacon_help_offer_admission_events.dart';
import 'table/capability_evidence_edges.dart';
import 'table/capability_evidence_generations.dart';
import 'table/capability_routing_mutes.dart';
import 'table/constellation_anchor_cursors.dart';
import 'table/constellation_anchors.dart';
import 'table/beacon_commitment_events.dart';
import 'table/beacon_help_offer_coordinations.dart';
import 'table/beacon_activity_events.dart';
import 'table/beacon_fact_card_revisions.dart';
import 'table/beacon_fact_cards.dart';
import 'table/beacon_forward_edges.dart';
import 'table/beacon_images.dart';
import 'table/beacon_image_stages.dart';
import 'table/beacons.dart';
import 'table/beacon_participants.dart';
import 'table/beacon_room_message_attachments.dart';
import 'table/beacon_room_message_reactions.dart';
import 'table/coordination_items.dart';
import 'table/ego_witness_windows.dart';
import 'table/beacon_room_messages.dart';
import 'table/beacon_items_seen.dart';
import 'table/beacon_people_seen.dart';
import 'table/beacon_room_seen.dart';
import 'table/beacon_room_states.dart';
import 'table/beacon_stewards.dart';
import 'table/complaints.dart';
import 'table/fcm_tokens.dart';
import 'table/images.dart';
import 'table/image_object_gcs.dart';
import 'table/inbox_items.dart';
import 'table/invite_genealogy.dart';
import 'table/invite_seed_prompt_state.dart';
import 'table/invitations.dart';
import 'table/pollings.dart';
import 'table/polling_acts.dart';
import 'table/polling_variants.dart';
import 'table/person_capability_events.dart';
import 'table/user_block_intents.dart';
import 'table/user_blocks.dart';
import 'table/user_contacts.dart';
import 'table/user_availability.dart';
import 'table/user_presence.dart';
import 'table/users.dart';
import 'table/forward_decision_attributions.dart';
import 'table/mr_publish_epochs.dart';
import 'table/user_trust_edges.dart';
import 'table/vote_users.dart';

export 'package:drift/drift.dart';
export 'package:postgres/src/exceptions.dart';

part 'tentura_db.g.dart';

@singleton
@DriftDatabase(
  tables: [
    AccountCredentials,
    AccountVerifiedContacts,
    AccountSessions,
    EmailAuthTransactions,
    BeaconHelpOffers,
    BeaconHelpOfferAdmissionEvents,
    BeaconCommitmentEvents,
    CapabilityEvidenceEdges,
    CapabilityEvidenceGenerations,
    CapabilityRoutingMutes,
    BeaconHelpOfferCoordinations,
    BeaconActivityEvents,
    BeaconFactCards,
    BeaconFactCardRevisions,
    BeaconForwardEdges,
    BeaconImages,
    BeaconImageStages,
    ForwardDecisionAttributions,
    BeaconParticipants,
    BeaconRoomMessageAttachments,
    BeaconRoomMessageReactions,
    CoordinationItems,
    EgoWitnessWindows,
    BeaconRoomMessages,
    BeaconRoomSeen,
    BeaconItemsSeen,
    BeaconPeopleSeen,
    BeaconRoomStates,
    BeaconStewards,
    Beacons,
    ConstellationAnchorCursors,
    ConstellationAnchors,
    Complaints,
    FcmTokens,
    Images,
    ImageObjectGcs,
    InboxItems,
    InviteGenealogy,
    InviteSeedPromptStates,
    Invitations,
    MrPublishEpochs,
    PersonCapabilityEvents,
    Pollings,
    PollingActs,
    PollingVariants,
    Users,
    UserBlockIntents,
    UserBlocks,
    UserContacts,
    UserAvailability,
    UserPresence,
    UserTrustEdges,
    VoteUsers,
  ],
)
class TenturaDb extends _$TenturaDb {
  static final Object _mutatingTransactionZoneKey = Object();

  @factoryMethod
  TenturaDb(Env env)
    // Pool must keep maxConnectionCount == 1. Drift issues
    // BEGIN/COMMIT/SAVEPOINT via NoTransactionDelegate as ordinary
    // session.execute() calls; Pool.execute releases the connection after each
    // statement, and the pool may replace an aged connection between two
    // statements (maxConnectionAge / maxSessionUse). That put SAVEPOINT on a
    // fresh session outside the transaction (25P01: TENTURA-SERVER-G/H).
    // _PinnedPoolSession holds one pool connection for a whole transaction.
    // With DRIFT_TRANSACTION_PINNED_POOL_ENABLED (spike #227) the executor
    // itself leases a connection per transaction, so the pool may be larger.
    : this._(
        Pool<dynamic>.withEndpoints(
          [env.pgEndpoint],
          settings: env.pgPoolSettings,
        ),
        env,
      );

  TenturaDb._(Pool<dynamic> pool, Env env)
    : this._session(
        env.driftTransactionPinnedPoolEnabled ? null : _PinnedPoolSession(pool),
        pool,
        env,
      );

  TenturaDb._session(_PinnedPoolSession? session, Pool<dynamic> pool, Env env)
    : _pinnedSession = session,
      super(
        session == null
            ? _TransactionPinnedPgDatabase(
                pool,
                logStatements: env.isDebugModeOn,
              )
            : PgDatabase.opened(
                session,
                enableMigrations: false,
                logStatements: env.isDebugModeOn,
              ),
      );

  TenturaDb.forTest({required QueryExecutor database})
    : _pinnedSession = null,
      super(database);

  final _PinnedPoolSession? _pinnedSession;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    final session = _pinnedSession;
    if (session == null) {
      return super.transaction(action, requireNew: requireNew);
    }
    await session.pin();
    try {
      return await super.transaction(action, requireNew: requireNew);
    } finally {
      session.unpin();
    }
  }

  @override
  int get schemaVersion => 1;

  /// Whether [action] is running inside [withMutatingUser] or
  /// [withMutatingSystem] on this database (including nested re-entry).
  bool get isInAmbientMutatingTransaction {
    final current = Zone.current[_mutatingTransactionZoneKey];
    return current is _MutatingTransactionContext && identical(current.db, this);
  }

  /// The connector's per-backend `mr_rpc_attempts()` counter on the connection
  /// this database runs on (readable inside an open transaction), so the
  /// RPC-count gate can take deltas around a transaction or batch.
  Future<int> mrRpcAttempts() async {
    final row = await customSelect(
      'SELECT public.mr_rpc_attempts() AS attempts',
    ).getSingle();
    return row.read<int>('attempts');
  }

  /// Runs [action] in a transaction with `tentura.mutating_user_id` set to
  /// [userId]. Realtime publishers attach this actor context to invalidations;
  /// router compatibility policy, not this transaction boundary, decides
  /// whether the actor's sessions receive the hint.
  Future<T> withMutatingUser<T>(
    String userId,
    Future<T> Function() action,
  ) async {
    final current = Zone.current[_mutatingTransactionZoneKey];
    if (current is _MutatingTransactionContext && identical(current.db, this)) {
      if (current.actorUserId != userId) {
        throw StateError(
          'Nested mutating actor mismatch: '
          '${current.actorUserId ?? '<system>'} != $userId',
        );
      }
      return action();
    }
    return transaction(() async {
      // `customStatement` binds raw Dart values; do not pass drift `Variable`
      // here (unlike `customSelect`).
      await customStatement(
        r"SELECT set_config('tentura.mutating_user_id', $1, true)",
        [userId],
      );
      return runZoned(
        action,
        zoneValues: {
          _mutatingTransactionZoneKey: _MutatingTransactionContext(this, userId),
        },
      );
    });
  }

  /// Like [withMutatingUser] but in a REPEATABLE READ READ WRITE transaction,
  /// retried as a whole on 40001/40P01 (at most [maxAttempts], jittered
  /// backoff slept after rollback with the connection released, bounded by
  /// [deadline]). Each attempt's statements are bounded by the request budget
  /// through a transaction-local `statement_timeout`: [deadline] on the first
  /// attempt, what is left of it on a retry.
  Future<T> withMutatingRepeatableRead<T>(
    String userId,
    Future<T> Function() action, {
    Duration deadline = const Duration(seconds: 5),
    int maxAttempts = 3,
    Future<void> Function(Duration)? sleep,
  }) {
    final current = Zone.current[_mutatingTransactionZoneKey];
    if (current is _MutatingTransactionContext && identical(current.db, this)) {
      return withMutatingUser(userId, action);
    }
    final clock = Stopwatch()..start();
    var attempt = 0;
    return withPostgresBoundedRetry(
      () => transaction(() async {
        final budget = attempt++ == 0 ? deadline : deadline - clock.elapsed;
        final budgetMs = max(1, budget.inMilliseconds);
        await customStatement(
          'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ WRITE',
        );
        await customStatement(
          r"SELECT set_config('tentura.mutating_user_id', $1, true), "
          r"set_config('statement_timeout', $2, true)",
          [userId, '$budgetMs'],
        );
        return runZoned(
          action,
          zoneValues: {
            _mutatingTransactionZoneKey: _MutatingTransactionContext(
              this,
              userId,
            ),
          },
        );
      }),
      deadline: deadline,
      maxAttempts: maxAttempts,
      sleep: sleep,
    );
  }

  /// System-owned mutation transaction with an explicitly empty actor scope.
  /// One PostgreSQL MVCC snapshot for repeatable-read field reads (C4).
  Future<T> withReadSnapshot<T>(Future<T> Function() action) {
    return transaction(() async {
      await customStatement(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
      );
      return action();
    });
  }

  /// Makes the rest of the current transaction keep its first visible-set
  /// computation per (viewer, context); see m0230.
  Future<void> freezeVisibilityMemo() => customStatement(
    "SELECT set_config('tentura_visibility.frozen', 'on', true)",
  );

  Future<T> withMutatingSystem<T>(Future<T> Function() action) {
    final current = Zone.current[_mutatingTransactionZoneKey];
    if (current is _MutatingTransactionContext && identical(current.db, this)) {
      if (current.actorUserId != null) {
        throw StateError('Cannot enter a system mutation inside an actor mutation');
      }
      return action();
    }
    return transaction(
      () => runZoned(
        action,
        zoneValues: {
          _mutatingTransactionZoneKey: _MutatingTransactionContext(this, null),
        },
      ),
    );
  }

  @disposeMethod
  Future<void> dispose() => super.close();
}

final class _MutatingTransactionContext {
  const _MutatingTransactionContext(this.db, this.actorUserId);

  final TenturaDb db;
  final String? actorUserId;
}

/// [Session] over a [Pool] that, while pinned, runs every statement on one
/// pool connection so a transaction never spans two backend sessions.
final class _PinnedPoolSession implements Session {
  _PinnedPoolSession(this._pool);

  final Pool<dynamic> _pool;

  Session? _pinned;
  Completer<void>? _release;
  Future<void>? _pinning;
  int _pins = 0;

  /// While a pin is being acquired a statement must wait for it: going to the
  /// pool instead would queue behind the pinned connection while holding
  /// Drift's executor lock that the pinning transaction needs (deadlock).
  Future<Session> _session() async {
    if (_pins > 0) {
      await _pinning;
    }
    return _pinned ?? _pool;
  }

  Future<void> pin() async {
    _pins++;
    if (_pins > 1) {
      await _pinning;
      return;
    }
    final ready = Completer<void>();
    final release = _release = Completer<void>();
    _pinning = ready.future;
    unawaited(
      _pool
          .withConnection((connection) {
            _pinned = connection;
            ready.complete();
            return release.future;
          })
          .catchError((Object e, StackTrace st) {
            if (!ready.isCompleted) ready.completeError(e, st);
          }),
    );
    try {
      await ready.future;
    } catch (_) {
      _pins = 0;
      rethrow;
    }
  }

  void unpin() {
    if (_pins == 0) return;
    if (--_pins > 0) return;
    _pinned = null;
    _release?.complete();
    _release = null;
  }

  @override
  bool get isOpen => _pool.isOpen;

  @override
  Future<void> get closed => _pool.closed;

  @override
  Future<Statement> prepare(Object query) async =>
      (await _session()).prepare(query);

  @override
  Future<Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) async {
    final session = await _session();
    if (session is! Pool) {
      return session.execute(
        query,
        parameters: parameters,
        ignoreRows: ignoreRows,
        queryMode: queryMode,
        timeout: timeout,
      );
    }
    // Pool.execute disposes its connection whenever the statement throws. A
    // statement cancelled by statement_timeout (57014) leaves the connection
    // healthy, so report server errors out of the callback and rethrow them
    // after the connection went back to the pool.
    final (result, error, trace) = await _pool.withConnection((
      connection,
    ) async {
      try {
        final result = await connection.execute(
          query,
          parameters: parameters,
          ignoreRows: ignoreRows,
          queryMode: queryMode,
          timeout: timeout,
        );
        return (result, null, null);
      } on ServerException catch (e, s) {
        return (null, e, s);
      }
    });
    if (error != null) Error.throwWithStackTrace(error, trace!);
    return result!;
  }
}

/// Spike (#227): a Postgres [DelegatedDatabase] whose transactions each lease
/// one pooled connection ([Connection.runTx]) and run nested transactions as
/// savepoints on it, so a multi-connection pool cannot split a transaction.
final class _TransactionPinnedPgDatabase extends DelegatedDatabase {
  _TransactionPinnedPgDatabase(Pool<dynamic> pool, {super.logStatements})
    : super(_TransactionPinnedDelegate(pool), isSequential: true);

  @override
  SqlDialect get dialect => SqlDialect.postgres;
}

final class _TransactionPinnedDelegate extends DatabaseDelegate {
  _TransactionPinnedDelegate(Pool<dynamic> pool)
    : _root = PgDatabase.opened(
        _PinnedPoolSession(pool),
        enableMigrations: false,
      ).delegate,
      transactionDelegate = _PinnedTransactionDelegate(pool);

  final DatabaseDelegate _root;

  @override
  final TransactionDelegate transactionDelegate;

  @override
  final DbVersionDelegate versionDelegate = const NoVersionDelegate();

  @override
  Future<bool> get isOpen async => await _root.isOpen;

  @override
  Future<void> open(QueryExecutorUser user) => _root.open(user);

  @override
  Future<void> close() => _root.close();

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _root.runBatched(statements);

  @override
  Future<void> runCustom(String statement, List<Object?> args) =>
      _root.runCustom(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _root.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _root.runUpdate(statement, args);

  @override
  Future<QueryResult> runSelect(String statement, List<Object?> args) =>
      _root.runSelect(statement, args);
}

final class _PinnedTransactionDelegate extends SupportedTransactionDelegate {
  _PinnedTransactionDelegate(this._pool);

  final Pool<dynamic> _pool;
  var _savepoints = 0;

  @override
  Future<void> startTransaction(Future<void> Function(QueryDelegate) run) =>
      _pool.withConnection(
        (connection) => connection.runTx((tx) async {
          final delegate = PgDatabase.opened(
            tx,
            enableMigrations: false,
          ).delegate;
          await delegate.open(const _NoopExecutorUser());
          await run(delegate);
        }),
      );

  @override
  Future<void> Function(
    QueryDelegate outer,
    Future<void> Function(QueryDelegate) block,
  )
  get startNested => (outer, block) async {
    final name = 'tentura_sp_${_savepoints++}';
    await outer.runCustom('SAVEPOINT $name', const []);
    try {
      await block(outer);
    } catch (_) {
      await outer.runCustom('ROLLBACK TO SAVEPOINT $name', const []);
      rethrow;
    }
    await outer.runCustom('RELEASE SAVEPOINT $name', const []);
  };
}

final class _NoopExecutorUser implements QueryExecutorUser {
  const _NoopExecutorUser();

  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
