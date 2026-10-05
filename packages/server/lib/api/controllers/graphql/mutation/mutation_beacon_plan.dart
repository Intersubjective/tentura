import 'dart:convert';

import 'package:tentura_server/domain/use_case/beacon_plan_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Request plan («либретто», #220) writes. Save, restore and «Не успеваю»
/// return `PlanSaveOutcome` as JSON; tick and ack return `true`.
final class MutationBeaconPlan extends GqlNodeBase {
  MutationBeaconPlan({BeaconPlanCase? beaconPlanCase})
    : _case = beaconPlanCase ?? GetIt.I<BeaconPlanCase>();

  final BeaconPlanCase _case;

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  final _stepId = InputFieldString(fieldName: 'stepId');

  final _stepsJson = InputFieldString(fieldName: 'stepsJson');

  final _comment = InputFieldString(fieldName: 'comment');

  final _option = InputFieldString(fieldName: 'option');

  final _toUserId = InputFieldString(fieldName: 'toUserId');

  final _excerpt = InputFieldString(fieldName: 'excerpt');

  final _baseRevisionSeq = InputFieldInt(fieldName: 'baseRevisionSeq');

  final _fromSeq = InputFieldInt(fieldName: 'fromSeq');

  final _uptoSeq = InputFieldInt(fieldName: 'uptoSeq');

  final _done = InputFieldBool(fieldName: 'done');

  final _newStartAt = InputFieldDatetime(fieldName: 'newStartAt');

  final _newEndAt = InputFieldDatetime(fieldName: 'newEndAt');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconPlanSave,
    beaconPlanRestore,
    beaconPlanStepSetDone,
    beaconPlanAck,
    beaconPlanStepCantMake,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconPlanSave => GraphQLObjectField(
    'beaconPlanSave',
    graphQLString.nonNullable(),
    arguments: [
      _beaconId.field,
      _baseRevisionSeq.fieldNonNullable,
      _stepsJson.field,
      _comment.fieldNullable,
    ],
    resolve: (_, args) async {
      final outcome = await _case.save(
        actorId: getCredentials(args).sub,
        beaconId: _beaconId.fromArgsNonNullable(args),
        baseSeq: _baseRevisionSeq.fromArgsNonNullable(args),
        stepsJson: _stepsJson.fromArgsNonNullable(args),
        comment: _comment.fromArgs(args) ?? '',
      );
      return jsonEncode(outcome.toJson());
    },
  );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanRestore =>
      GraphQLObjectField(
        'beaconPlanRestore',
        graphQLString.nonNullable(),
        arguments: [
          _beaconId.field,
          _fromSeq.fieldNonNullable,
          _baseRevisionSeq.fieldNonNullable,
        ],
        resolve: (_, args) async {
          final outcome = await _case.restore(
            actorId: getCredentials(args).sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
            fromSeq: _fromSeq.fromArgsNonNullable(args),
            baseSeq: _baseRevisionSeq.fromArgsNonNullable(args),
          );
          return jsonEncode(outcome.toJson());
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanStepSetDone =>
      GraphQLObjectField(
        'beaconPlanStepSetDone',
        graphQLBoolean.nonNullable(),
        arguments: [_stepId.field, _done.field],
        resolve: (_, args) async {
          await _case.setDone(
            actorId: getCredentials(args).sub,
            stepId: _stepId.fromArgsNonNullable(args),
            done: _done.fromArgsNonNullable(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanAck => GraphQLObjectField(
    'beaconPlanAck',
    graphQLBoolean.nonNullable(),
    arguments: [_beaconId.field, _uptoSeq.fieldNonNullable],
    resolve: (_, args) async {
      await _case.ack(
        actorId: getCredentials(args).sub,
        beaconId: _beaconId.fromArgsNonNullable(args),
        uptoSeq: _uptoSeq.fromArgsNonNullable(args),
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get beaconPlanStepCantMake =>
      GraphQLObjectField(
        'beaconPlanStepCantMake',
        graphQLString.nonNullable(),
        arguments: [
          _stepId.field,
          _option.field,
          _baseRevisionSeq.fieldNonNullable,
          _newStartAt.fieldNullable,
          _newEndAt.fieldNullable,
          _toUserId.fieldNullable,
          _excerpt.fieldNullable,
        ],
        resolve: (_, args) async {
          final outcome = await _case.cantMake(
            actorId: getCredentials(args).sub,
            stepId: _stepId.fromArgsNonNullable(args),
            option: _option.fromArgsNonNullable(args),
            baseSeq: _baseRevisionSeq.fromArgsNonNullable(args),
            newStartAt: _newStartAt.fromArgs(args),
            newEndAt: _newEndAt.fromArgs(args),
            toUserId: _toUserId.fromArgs(args),
            excerpt: _excerpt.fromArgs(args) ?? '',
          );
          return jsonEncode(outcome.toJson());
        },
      );
}
