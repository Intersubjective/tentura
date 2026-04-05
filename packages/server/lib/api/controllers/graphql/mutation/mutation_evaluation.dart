import 'package:tentura_server/domain/use_case/evaluation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationEvaluation extends GqlNodeBase {
  MutationEvaluation({EvaluationCase? evaluationCase})
    : _evaluationCase = evaluationCase ?? GetIt.I<EvaluationCase>();

  final EvaluationCase _evaluationCase;

  final _evaluatedUserId = InputFieldString(fieldName: 'evaluatedUserId');

  final _note = InputFieldString(fieldName: 'note');

  final GraphQLFieldInput<List<String>, List<String>> _reasonTagsField =
      GraphQLFieldInput(
        'reasonTags',
        GraphQLListType(graphQLString.nonNullable()),
      );

  final GraphQLFieldInput<int, int> _valueField = GraphQLFieldInput(
    'value',
    graphQLInt.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconCloseWithReview,
    evaluationSubmit,
    evaluationFinalize,
    evaluationSkip,
    evaluationDraftSave,
    evaluationDraftDelete,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconCloseWithReview =>
      GraphQLObjectField(
        'beaconCloseWithReview',
        gqlTypeBeaconCloseReviewResult.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.beaconCloseWithReview(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationSubmit =>
      GraphQLObjectField(
        'evaluationSubmit',
        graphQLBoolean.nonNullable(),
        arguments: [
          InputFieldId.field,
          _evaluatedUserId.field,
          _valueField,
          _reasonTagsField,
          _note.fieldNullable,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          final tags = args[_reasonTagsField.name];
          final list = tags == null
              ? <String>[]
              : List<String>.from(tags as List);
          return _evaluationCase.evaluationSubmit(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            evaluatorId: jwt.sub,
            evaluatedUserId: _evaluatedUserId.fromArgsNonNullable(args),
            value: args[_valueField.name]! as int,
            reasonTags: list,
            note: _note.fromArgs(args) ?? '',
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationFinalize =>
      GraphQLObjectField(
        'evaluationFinalize',
        graphQLBoolean.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.evaluationFinalize(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationSkip =>
      GraphQLObjectField(
        'evaluationSkip',
        graphQLBoolean.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.evaluationSkip(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationDraftSave =>
      GraphQLObjectField(
        'evaluationDraftSave',
        graphQLBoolean.nonNullable(),
        arguments: [
          InputFieldId.field,
          _evaluatedUserId.field,
          _valueField,
          _reasonTagsField,
          _note.fieldNullable,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          final tags = args[_reasonTagsField.name];
          final list = tags == null
              ? <String>[]
              : List<String>.from(tags as List);
          return _evaluationCase.evaluationDraftSave(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            evaluatorId: jwt.sub,
            evaluatedUserId: _evaluatedUserId.fromArgsNonNullable(args),
            value: args[_valueField.name]! as int,
            reasonTags: list,
            note: _note.fromArgs(args) ?? '',
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationDraftDelete =>
      GraphQLObjectField(
        'evaluationDraftDelete',
        graphQLBoolean.nonNullable(),
        arguments: [InputFieldId.field, _evaluatedUserId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.evaluationDraftDelete(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            evaluatorId: jwt.sub,
            evaluatedUserId: _evaluatedUserId.fromArgsNonNullable(args),
          );
        },
      );
}
