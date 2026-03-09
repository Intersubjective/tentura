import 'package:graphql_schema2/graphql_schema2.dart';

import 'mutation_auth.dart';
import 'mutation_beacon.dart';
import 'mutation_complaint.dart';
import 'mutation_fcm.dart';
import 'mutation_invitation.dart';
import 'mutation_meritrank.dart';
import 'mutation_polling.dart';
import 'mutation_user.dart';

List<GraphQLObjectField<dynamic, dynamic>> get mutationsAll => [
  ...MutationAuth().all,
  ...MutationBeacon().all,
  ...MutationComplaint().all,
  ...MutationInvitation().all,
  ...MutationMeritrank().all,
  ...MutationPolling().all,
  ...MutationUser().all,
  ...MutationFcm().all,
];
