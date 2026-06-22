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

import 'custom_types/mentions_text_array_type.dart';
import 'table/account_credentials.dart';
import 'table/account_verified_contacts.dart';
import 'table/account_sessions.dart';
import 'table/email_auth_transactions.dart';
import 'table/beacon_help_offers.dart';
import 'table/beacon_help_offer_coordinations.dart';
import 'table/beacon_evaluation_participants.dart';
import 'table/beacon_evaluation_visibility.dart';
import 'table/beacon_evaluations.dart';
import 'table/beacon_activity_events.dart';
import 'table/beacon_fact_cards.dart';
import 'table/beacon_forward_edges.dart';
import 'table/beacon_images.dart';
import 'table/beacon_review_statuses.dart';
import 'table/beacon_review_windows.dart';
import 'table/beacons.dart';
import 'table/beacon_participants.dart';
import 'table/beacon_room_message_attachments.dart';
import 'table/beacon_room_message_reactions.dart';
import 'table/coordination_items.dart';
import 'table/beacon_room_messages.dart';
import 'table/beacon_items_seen.dart';
import 'table/beacon_room_seen.dart';
import 'table/beacon_room_states.dart';
import 'table/beacon_stewards.dart';
import 'table/complaints.dart';
import 'table/fcm_tokens.dart';
import 'table/images.dart';
import 'table/inbox_items.dart';
import 'table/invitations.dart';
import 'table/pollings.dart';
import 'table/polling_acts.dart';
import 'table/polling_variants.dart';
import 'table/person_capability_events.dart';
import 'table/user_contacts.dart';
import 'table/user_presence.dart';
import 'table/users.dart';
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
    BeaconHelpOfferCoordinations,
    BeaconEvaluationParticipants,
    BeaconEvaluationVisibility,
    BeaconEvaluations,
    BeaconActivityEvents,
    BeaconFactCards,
    BeaconForwardEdges,
    BeaconImages,
    BeaconReviewStatuses,
    BeaconReviewWindows,
    BeaconParticipants,
    BeaconRoomMessageAttachments,
    BeaconRoomMessageReactions,
    CoordinationItems,
    BeaconRoomMessages,
    BeaconRoomSeen,
    BeaconItemsSeen,
    BeaconRoomStates,
    BeaconStewards,
    Beacons,
    Complaints,
    FcmTokens,
    Images,
    InboxItems,
    Invitations,
    PersonCapabilityEvents,
    Pollings,
    PollingActs,
    PollingVariants,
    Users,
    UserContacts,
    UserPresence,
    UserTrustEdges,
    VoteUsers,
  ],
)
class TenturaDb extends _$TenturaDb {
  @factoryMethod
  TenturaDb(Env env)
    : super(
        PgDatabase.opened(
          Pool<dynamic>.withEndpoints(
            [env.pgEndpoint],
            settings: env.pgPoolSettings,
          ),
          enableMigrations: false,
          logStatements: env.isDebugModeOn,
        ),
      );

  TenturaDb.forTest({required PgDatabase database}) : super(database);

  @override
  int get schemaVersion => 1;

  /// Runs [action] inside a transaction with the `tentura.mutating_user_id`
  /// GUC set to [userId], so `notify_entity_change()` can suppress the
  /// echo notification back to the originating user.
  Future<T> withMutatingUser<T>(
    String userId,
    Future<T> Function() action,
  ) => transaction(() async {
    // `customStatement` binds raw Dart values; do not pass drift `Variable`
    // here (unlike `customSelect`).
    await customStatement(
      r"SELECT set_config('tentura.mutating_user_id', $1, true)",
      [userId],
    );
    return action();
  });

  @disposeMethod
  Future<void> dispose() => super.close();
}
