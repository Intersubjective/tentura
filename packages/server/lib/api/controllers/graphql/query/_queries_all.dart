import 'package:graphql_schema2/graphql_schema2.dart';

import 'query_beacon_involvement.dart';
import 'query_beacon_room.dart';
import 'query_capability.dart';
import 'query_coordination.dart';
import 'query_evaluation.dart';
import 'query_fact_card.dart';
import 'query_forward_graph.dart';
import 'query_forward_reasons.dart';
import 'query_invitation.dart';
import 'query_mutual_friends.dart';
import 'query_version.dart';

List<GraphQLObjectField<dynamic, dynamic>> get queriesAll => [
  ...QueryInvitation().all,
  ...QueryBeaconInvolvement().all,
  ...QueryBeaconRoom().all,
  ...QueryCapability().all,
  ...QueryCoordination().all,
  ...QueryEvaluation().all,
  ...QueryFactCard().all,
  ...QueryForwardGraph().all,
  ...QueryForwardReasons().all,
  ...QueryMutualFriends().all,
  queryVersion,
];
