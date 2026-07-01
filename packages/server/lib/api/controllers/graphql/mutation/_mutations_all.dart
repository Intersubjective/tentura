import 'package:graphql_schema2/graphql_schema2.dart';

import 'mutation_auth.dart';
import 'mutation_beacon_room.dart';
import 'mutation_beacon.dart';
import 'mutation_capability.dart';
import 'mutation_help_offer.dart';
import 'mutation_coordination.dart';
import 'mutation_complaint.dart';
import 'mutation_contact.dart';
import 'mutation_evaluation.dart';
import 'mutation_fact_card.dart';
import 'mutation_fcm.dart';
import 'mutation_forward.dart';
import 'mutation_invitation.dart';
import 'mutation_meritrank.dart';
import 'mutation_notification_center.dart';
import 'mutation_notification_preferences.dart';
import 'mutation_polling.dart';
import 'mutation_coordination_item.dart';
import 'mutation_debug.dart';
import 'mutation_user.dart';
import 'mutation_user_vote.dart';

List<GraphQLObjectField<dynamic, dynamic>> get mutationsAll => [
  ...MutationAuth().all,
  ...MutationBeacon().all,
  ...MutationBeaconRoom().all,
  ...MutationCapability().all,
  ...MutationHelpOffer().all,
  ...MutationCoordination().all,
  ...MutationComplaint().all,
  ...MutationContact().all,
  ...MutationEvaluation().all,
  ...MutationFactCard().all,
  ...MutationForward().all,
  ...MutationInvitation().all,
  ...MutationMeritrank().all,
  ...MutationPolling().all,
  ...MutationCoordinationItem().all,
  ...MutationUser().all,
  ...MutationUserVote().all,
  ...MutationFcm().all,
  ...MutationDebug().all,
  ...MutationNotificationCenter().all,
  ...MutationNotificationPreferences().all,
];
