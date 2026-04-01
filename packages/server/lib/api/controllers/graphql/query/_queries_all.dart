import 'package:graphql_schema2/graphql_schema2.dart';

import 'query_beacon_involvement.dart';
import 'query_evaluation.dart';
import 'query_invitation.dart';
import 'query_version.dart';

List<GraphQLObjectField<dynamic, dynamic>> get queriesAll => [
  ...QueryInvitation().all,
  ...QueryBeaconInvolvement().all,
  ...QueryEvaluation().all,
  queryVersion,
];
