import 'package:graphql_schema2/graphql_schema2.dart';

import 'query_beacon_display.dart';
import 'query_beacon_hierarchy.dart';
import 'query_attention.dart';
import 'query_beacon_involvement.dart';
import 'query_beacon_member_webs.dart';
import 'query_beacon_plan.dart';
import 'query_beacon_room.dart';
import 'query_capability.dart';
import 'query_capability_projection.dart';
import 'query_invite_seed_prompt.dart';
import 'query_closure.dart';
import 'query_contact.dart';
import 'query_help_offerer_forward_path.dart';
import 'query_coordination.dart';
import 'query_fact_card.dart';
import 'query_forward_candidates.dart';
import 'query_constellation_field.dart';
import 'query_forward_candidate_context.dart';
import 'query_forward_graph.dart';
import 'query_forward_inbound.dart';
import 'query_forward_reasons.dart';
import 'query_invite_genealogy.dart';
import 'query_invitation.dart';
import 'query_mutual_friends.dart';
import 'query_lineage_suggestions.dart';
import 'query_person_shared_contexts.dart';
import 'query_notification_preferences.dart';
import 'query_trust_preference.dart';
import 'query_user_block.dart';
import 'query_version.dart';
import 'query_post.dart';

List<GraphQLObjectField<dynamic, dynamic>> get queriesAll => [
  ...QueryAttention().all,
  ...QueryBeaconDisplay().all,
  ...QueryBeaconHierarchy().all,
  ...QueryInvitation().all,
  ...QueryInviteGenealogy().all,
  ...QueryBeaconInvolvement().all,
  ...QueryBeaconMemberWebs().all,
  ...QueryBeaconPlan().all,
  ...QueryBeaconRoom().all,
  ...QueryPost().all,
  ...QueryCapability().all,
  ...QueryCapabilityProjection().all,
  ...QueryInviteSeedPrompt().all,
  ...QueryClosure().all,
  ...QueryContact().all,
  ...QueryHelpOffererForwardPath().all,
  ...QueryCoordination().all,
  ...QueryFactCard().all,
  ...QueryForwardCandidates().all,
  ...QueryConstellationField().all,
  ...QueryForwardCandidateContext().all,
  ...QueryForwardGraph().all,
  ...QueryForwardInbound().all,
  ...QueryForwardReasons().all,
  ...QueryMutualFriends().all,
  ...QueryLineageSuggestions().all,
  ...QueryNotificationPreferences().all,
  ...QueryPersonSharedContexts().all,
  ...QueryTrustPreference().all,
  ...QueryUserBlock().all,
  queryVersion,
];
