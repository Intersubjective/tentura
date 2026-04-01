import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart';
import 'package:postgres/postgres.dart';
import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/beacon_update_entity.dart';
import 'package:tentura_server/domain/entity/comment_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/invitation_entity.dart';
import 'package:tentura_server/domain/entity/opinion_entity.dart';
import 'package:tentura_server/domain/entity/polling_entity.dart';
import 'package:tentura_server/domain/entity/polling_variant_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

import 'table/beacon_commitments.dart';
import 'table/beacon_evaluation_participants.dart';
import 'table/beacon_evaluation_visibility.dart';
import 'table/beacon_evaluations.dart';
import 'table/beacon_forward_edges.dart';
import 'table/beacon_review_statuses.dart';
import 'table/beacon_review_windows.dart';
import 'table/beacon_updates.dart';
import 'table/beacons.dart';
import 'table/comments.dart';
import 'table/complaints.dart';
import 'table/fcm_tokens.dart';
import 'table/images.dart';
import 'table/inbox_items.dart';
import 'table/invitations.dart';
import 'table/opinions.dart';
import 'table/p2p_messages.dart';
import 'table/pollings.dart';
import 'table/polling_acts.dart';
import 'table/polling_variants.dart';
import 'table/user_presence.dart';
import 'table/users.dart';
import 'table/vote_users.dart';

export 'package:drift/drift.dart';
export 'package:postgres/src/exceptions.dart';

part 'tentura_db.g.dart';

@singleton
@DriftDatabase(
  tables: [
    BeaconCommitments,
    BeaconEvaluationParticipants,
    BeaconEvaluationVisibility,
    BeaconEvaluations,
    BeaconForwardEdges,
    BeaconReviewStatuses,
    BeaconReviewWindows,
    BeaconUpdates,
    Beacons,
    Comments,
    Complaints,
    FcmTokens,
    Images,
    InboxItems,
    Invitations,
    Opinions,
    P2pMessages,
    Pollings,
    PollingActs,
    PollingVariants,
    Users,
    UserPresence,
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

  @disposeMethod
  Future<void> dispose() => super.close();
}
