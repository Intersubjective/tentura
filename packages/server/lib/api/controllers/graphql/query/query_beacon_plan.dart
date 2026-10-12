import 'dart:convert';

import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Request plan («либретто», #220) reads. Each returns one JSON document
/// (see `BeaconPlanCase.view` / `revisions` / `revision`).
final class QueryBeaconPlan extends GqlNodeBase {
  QueryBeaconPlan({BeaconPlanCase? beaconPlanCase})
    : _case = beaconPlanCase ?? GetIt.I<BeaconPlanCase>();

  final BeaconPlanCase _case;

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _beforeSeq = InputFieldInt(fieldName: 'beforeSeq');

  final _seq = InputFieldInt(fieldName: 'seq');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconPlan,
    beaconPlanRevisions,
    beaconPlanRevision,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconPlan => GraphQLObjectField(
    'beaconPlan',
    graphQLString.nonNullable(),
    arguments: [_beaconId.field],
    resolve: (_, args) async => jsonEncode(
      await _case.view(
        beaconId: _beaconId.fromArgsNonNullable(args),
        viewerId: getCredentials(args).sub,
      ),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanRevisions =>
      GraphQLObjectField(
        'beaconPlanRevisions',
        graphQLString.nonNullable(),
        arguments: [_beaconId.field, _beforeSeq.fieldNullable],
        resolve: (_, args) async => jsonEncode(
          await _case.revisions(
            beaconId: _beaconId.fromArgsNonNullable(args),
            viewerId: getCredentials(args).sub,
            beforeSeq: _beforeSeq.fromArgs(args),
          ),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanRevision =>
      GraphQLObjectField(
        'beaconPlanRevision',
        graphQLString.nonNullable(),
        arguments: [_beaconId.field, _seq.fieldNonNullable],
        resolve: (_, args) async => jsonEncode(
          await _case.revision(
            beaconId: _beaconId.fromArgsNonNullable(args),
            viewerId: getCredentials(args).sub,
            seq: _seq.fromArgsNonNullable(args),
          ),
        ),
      );
}
