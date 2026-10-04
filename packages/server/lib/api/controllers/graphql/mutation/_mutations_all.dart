import 'package:graphql_schema2/graphql_schema2.dart';

import 'mutation_auth.dart';
import 'mutation_availability.dart';
import 'mutation_attention.dart';
import 'mutation_beacon_people.dart';
import 'mutation_beacon_room.dart';
import 'mutation_beacon.dart';
import 'mutation_beacon_hierarchy.dart';
import 'mutation_capability.dart';
import 'mutation_capability_routing.dart';
import 'mutation_help_offer.dart';
import 'mutation_coordination.dart';
import 'mutation_constellation_anchor.dart';
import 'mutation_closure.dart';
import 'mutation_complaint.dart';
import 'mutation_contact.dart';
import 'mutation_fact_card.dart';
import 'mutation_fcm.dart';
import 'mutation_forward.dart';
import 'mutation_invitation.dart';
import 'mutation_meritrank.dart';
import 'mutation_notification_preferences.dart';
import 'mutation_polling.dart';
import 'mutation_room_baton.dart';
import 'mutation_post.dart';
import 'mutation_trust_preference.dart';
import 'mutation_debug.dart';
import 'mutation_user.dart';
import 'mutation_user_block.dart';
import 'mutation_user_vote.dart';

List<GraphQLObjectField<dynamic, dynamic>> get mutationsAll => [
  ...MutationAttention().all,
  ...MutationAuth().all,
  ...MutationBeacon().all,
  ...MutationBeaconHierarchy().all,
  ...MutationBeaconPeople().all,
  ...MutationBeaconRoom().all,
  ...MutationCapability().all,
  ...MutationCapabilityRouting().all,
  ...MutationHelpOffer().all,
  ...MutationCoordination().all,
  ...MutationConstellationAnchor().all,
  ...MutationClosure().all,
  ...MutationComplaint().all,
  ...MutationContact().all,
  ...MutationFactCard().all,
  ...MutationForward().all,
  ...MutationInvitation().all,
  ...MutationMeritrank().all,
  ...MutationPolling().all,
  ...MutationPost().all,
  ...MutationRoomBaton().all,
  ...MutationUser().all,
  ...MutationAvailability().all,
  ...MutationUserBlock().all,
  ...MutationUserVote().all,
  ...MutationFcm().all,
  ...MutationDebug().all,
  ...MutationNotificationPreferences().all,
  ...MutationTrustPreference().all,
];
