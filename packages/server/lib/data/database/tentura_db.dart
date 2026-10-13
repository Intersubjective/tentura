import 'dart:async';
import 'dart:math' show max;

import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart' show ServerException;
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

import 'db_pipeline_trace.dart';
import 'main_db_pool.dart';
import '../service/main_db_scope_admission.dart';
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
export '../service/main_db_scope_admission.dart' show MainDbWorkKind;
export 'package:postgres/src/exceptions.dart';

part 'tentura_db.g.dart';

@injectable
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
  static final Object _connectionScopeZoneKey = Object();
  static final Object _readSnapshotZoneKey = Object();

  /// [scopeInterceptor] is a test hook: it makes one interceptor per leased
  /// connection scope, wrapped around that scope's executor.
  TenturaDb(Env env, {QueryInterceptor Function()? scopeInterceptor})
    : this._(
        MainDbPool(env),
        ownsPool: true,
        scopeInterceptor: scopeInterceptor,
      );

  TenturaDb.auth(Env env) : this._(MainDbPool.auth(env), ownsPool: true);

  @factoryMethod
  TenturaDb.scoped(MainDbPool pool) : this._(pool);

  TenturaDb._(
    MainDbPool pool, {
    this._ownsPool = false,
    this._scopeInterceptor,
  }) : _mainPool = pool,
       super(
         DbSpanDatabase(
           PgDatabase.opened(
             pool.pool,
             enableMigrations: false,
             logStatements: pool.logStatements,
           ),
         ),
       );

  TenturaDb.forTest({required QueryExecutor database})
    : _mainPool = null,
      _ownsPool = false,
      _scopeInterceptor = null,
      super(database.interceptWith(DbSpanInterceptor()));

  final MainDbPool? _mainPool;
  final bool _ownsPool;
  final QueryInterceptor Function()? _scopeInterceptor;
  late final _PooledDatabaseUser _pooledUser = _PooledDatabaseUser(this);
  late final DbSpanConnectionUser _tracedUser = DbSpanConnectionUser(this);

  bool _sharesScope(TenturaDb other) =>
      identical(other, this) ||
      (_mainPool != null && identical(other._mainPool, _mainPool));

  _ScopedDatabaseUser? get _connectionScope {
    final scope = Zone.current[_connectionScopeZoneKey];
    if (scope is! _ScopedDatabaseUser ||
        !identical(scope.attachedDatabase._mainPool, _mainPool)) {
      return null;
    }
    if (!scope.isActive) {
      throw StateError('Database connection scope is closed');
    }
    return scope;
  }

  /// Drift's own zone key for the innermost transaction/savepoint user.
  static const Symbol _driftZoneRootUserKey = #DatabaseConnectionUser;

  @override
  DatabaseConnectionUser get resolvedEngine {
    // The innermost Drift transaction/savepoint takes precedence, whichever
    // TenturaDb instance over this pool opened it. Drift itself only matches a
    // zone transaction attached to `this`, so a savepoint opened by another
    // instance (e.g. a manager prefetch `transaction`) would otherwise resolve
    // to the bare scoped executor, which waits on the lock the savepoint holds.
    final fromZone = Zone.current[_driftZoneRootUserKey];
    if (fromZone is DatabaseConnectionUser) {
      // Drift marks the getter for overriding; reading it here is the same
      // check Drift's own resolvedEngine performs.
      // ignore: invalid_use_of_visible_for_overriding_member
      final owner = fromZone.attachedDatabase;
      if (owner is TenturaDb && _sharesScope(owner)) return fromZone;
    }
    return _connectionScope ?? (_mainPool == null ? _tracedUser : _pooledUser);
  }

  /// Carries admission metadata between batches without holding a connection.
  Future<T> withWorkContext<T>(
    Future<T> Function() action, {
    String? actorUserId,
    MainDbWorkKind kind = MainDbWorkKind.interactive,
  }) => MainDbWorkContext.run(
    action,
    actorUserId: actorUserId,
    kind: kind,
  );

  /// Gives all repositories using this database a private Drift executor over
  /// one leased connection. Nested calls retain the current transaction/lease.
  Future<T> withConnectionScope<T>(
    Future<T> Function() action, {
    String? actorUserId,
    MainDbWorkKind? kind,
  }) {
    final main = _mainPool;
    if (main == null || !identical(resolvedEngine, _pooledUser)) {
      return action();
    }
    final work = MainDbWorkContext.current;
    // Begun before admission so a queued scope's wait counts as acquire time.
    final trace = DbTransactionTrace.begin(this, leasesConnection: true);
    Future<T> admitted() => main.admission.run(
      () {
        Future<T> leased() => main.pool.withConnection((connection) async {
          final executor = DbSpanDatabase(
            PgDatabase.opened(
              connection,
              enableMigrations: false,
              logStatements: main.logStatements,
            ),
          );
          final scope = _ScopedDatabaseUser(
            this,
            _scopeInterceptor == null
                ? executor
                : executor.interceptWith(_scopeInterceptor()),
          );
          try {
            await trace?.acquired(connection: connection);
            return await runZoned(
              action,
              zoneValues: {_connectionScopeZoneKey: scope},
            );
          } on Object catch (error) {
            if (error is ServerException && error.code == '57014') {
              trace?.statementCancelled();
            }
            // A failed rollback must not return a dirty session to the pool.
            if (connection.isOpen &&
                (error is TimeoutException || error is! ServerException)) {
              await connection.close();
            }
            rethrow;
          } finally {
            scope.isActive = false;
            await scope.executor.close();
          }
        });
        return leased();
      },
      kind: kind ?? work?.kind ?? MainDbWorkKind.interactive,
      actorUserId: actorUserId ?? work?.actorUserId,
    );
    return trace == null ? admitted() : trace.run(admitted);
  }

  /// A transaction boundary with its own executor and connection lease.
  /// Drift owns BEGIN, nested SAVEPOINTs and COMMIT/ROLLBACK within that scope.
  Future<T> withTransaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
    String? actorUserId,
    MainDbWorkKind? kind,
  }) => withConnectionScope(
    () {
      final owner = _connectionScope?.attachedDatabase ?? this;
      final trace = DbTransactionTrace.begin(owner, leasesConnection: false);
      Future<T> run() => owner.transaction(action, requireNew: requireNew);
      return trace == null ? run() : trace.run(run);
    },
    actorUserId: actorUserId,
    kind: kind,
  );

  /// Runs [action] in the transaction already open on this scope, or in a new
  /// one when there is none. Unlike [withTransaction] it never opens a
  /// savepoint inside an existing unit of work.
  Future<T> withJoinedTransaction<T>(
    Future<T> Function() action, {
    String? actorUserId,
  }) {
    if (resolvedEngine.executor is TransactionExecutor) return action();
    return withTransaction(action, actorUserId: actorUserId);
  }

  @override
  int get schemaVersion => 1;

  /// Whether an action is running inside [withMutatingUser] or
  /// [withMutatingSystem] on this database (including nested re-entry).
  bool get isInAmbientMutatingTransaction {
    final current = Zone.current[_mutatingTransactionZoneKey];
    return current is _MutatingTransactionContext && _sharesScope(current.db);
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
    if (current is _MutatingTransactionContext && _sharesScope(current.db)) {
      if (current.actorUserId != userId) {
        throw StateError(
          'Nested mutating actor mismatch: '
          '${current.actorUserId ?? '<system>'} != $userId',
        );
      }
      return action();
    }
    return withTransaction(() async {
      // `customStatement` binds raw Dart values; do not pass drift `Variable`
      // here (unlike `customSelect`).
      await customStatement(
        r"SELECT set_config('tentura.mutating_user_id', $1, true)",
        [userId],
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
    }, actorUserId: userId);
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
    if (current is _MutatingTransactionContext && _sharesScope(current.db)) {
      if (!current.repeatableRead) {
        return Future.error(
          StateError('Cannot enter repeatable read inside read committed'),
        );
      }
      return withMutatingUser(userId, action);
    }
    final clock = Stopwatch()..start();
    var attempt = 0;
    return withPostgresBoundedRetry(
      () => withTransaction(() async {
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
              repeatableRead: true,
            ),
          },
        );
      }, actorUserId: userId),
      deadline: deadline,
      maxAttempts: maxAttempts,
      sleep: sleep,
    );
  }

  /// System-owned mutation transaction with an explicitly empty actor scope.
  /// One PostgreSQL MVCC snapshot for repeatable-read field reads (C4).
  Future<T> withReadSnapshot<T>(Future<T> Function() action) {
    if (_mainPool?.enforceGuards ?? false) {
      final open = Zone.current[_driftZoneRootUserKey];
      final owner = open is DatabaseConnectionUser
          // Match the owner just as Drift does in resolvedEngine.
          // ignore: invalid_use_of_visible_for_overriding_member
          ? open.attachedDatabase
          : null;
      if (owner is TenturaDb &&
          open is! _ScopedDatabaseUser &&
          Zone.current[_readSnapshotZoneKey] == null &&
          _sharesScope(owner)) {
        return Future.error(
          StateError(
            'Cannot start a read snapshot inside an open transaction: its '
            'isolation level is already fixed',
          ),
        );
      }
    }
    return withTransaction(
      () async {
        await customStatement(
          'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
        );
        return runZoned(
          action,
          zoneValues: {_readSnapshotZoneKey: true},
        );
      },
      kind: MainDbWorkKind.full,
    );
  }

  /// Makes the rest of the current transaction keep its first visible-set
  /// computation per (viewer, context); see m0230.
  Future<void> freezeVisibilityMemo() => customStatement(
    "SELECT set_config('tentura_visibility.frozen', 'on', true)",
  );

  Future<T> withMutatingSystem<T>(
    Future<T> Function() action, {
    MainDbWorkKind? kind,
  }) {
    final current = Zone.current[_mutatingTransactionZoneKey];
    if (current is _MutatingTransactionContext && _sharesScope(current.db)) {
      if (current.actorUserId != null) {
        throw StateError(
          'Cannot enter a system mutation inside an actor mutation',
        );
      }
      return action();
    }
    return withTransaction(
      () => runZoned(
        action,
        zoneValues: {
          _mutatingTransactionZoneKey: _MutatingTransactionContext(this, null),
        },
      ),
      kind: kind,
    );
  }

  @override
  Future<void> close() async {
    try {
      await super.close();
    } finally {
      if (_ownsPool) await _mainPool?.close();
    }
  }

  Future<void> dispose() => close();
}

final class _MutatingTransactionContext {
  const _MutatingTransactionContext(
    this.db,
    this.actorUserId, {
    this.repeatableRead = false,
  });

  final TenturaDb db;
  final String? actorUserId;
  final bool repeatableRead;
}

final class _ScopedDatabaseUser extends DatabaseConnectionUser {
  _ScopedDatabaseUser(this.attachedDatabase, QueryExecutor executor)
    : super.delegate(attachedDatabase, executor: executor);

  @override
  final TenturaDb attachedDatabase;
  bool isActive = true;

  @override
  Future<T> doWhenOpened<T>(FutureOr<T> Function(QueryExecutor e) fn) {
    if (!isActive) {
      return Future.error(
        StateError(
          'Database connection scope is closed: an executor reference was '
          'kept past its scope',
        ),
      );
    }
    if (attachedDatabase._mainPool?.enforceGuards ?? false) {
      final innermost = Zone.current[TenturaDb._driftZoneRootUserKey];
      final owner = innermost is DatabaseConnectionUser
          // Match the owner just as Drift does in resolvedEngine.
          // ignore: invalid_use_of_visible_for_overriding_member
          ? innermost.attachedDatabase
          : null;
      if (owner is TenturaDb &&
          !identical(innermost, this) &&
          attachedDatabase._sharesScope(owner)) {
        return Future.error(
          StateError(
            'Statement sent to a stale executor: the innermost executor is '
            '#${identityHashCode(innermost)} (expected), '
            'but the statement went to #${identityHashCode(this)} (actual)',
          ),
        );
      }
    }
    return super.doWhenOpened(fn);
  }
}

/// Routes inherited Drift operations through the same admission and lease as
/// explicit scopes, including the full lifetime of a transaction or batch.
final class _PooledDatabaseUser extends DatabaseConnectionUser {
  _PooledDatabaseUser(this.attachedDatabase) : super.delegate(attachedDatabase);

  @override
  final TenturaDb attachedDatabase;

  @override
  Future<T> doWhenOpened<T>(FutureOr<T> Function(QueryExecutor e) fn) =>
      attachedDatabase.withConnectionScope(
        () => attachedDatabase.resolvedEngine.doWhenOpened(fn),
      );
}
