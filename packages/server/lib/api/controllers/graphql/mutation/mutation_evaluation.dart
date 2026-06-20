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

  final _expectedRequiresReviewWindow = InputFieldBool(
    fieldName: 'expectedRequiresReviewWindow',
  );

  final GraphQLFieldInput<List<String>, List<String>> _reasonTagsField =
      GraphQLFieldInput(
        'reasonTags',
        GraphQLListType(graphQLString.nonNullable()),
      );

  final GraphQLFieldInput<int, int> _valueField = GraphQLFieldInput(
    'value',
    graphQLInt.nonNullable(),
  );

  /// Optional list of capability slugs the evaluator acknowledges for the
  /// evaluated person (close-acknowledgement source). Nullable outer list;
  /// non-null inner elements — per WORKAROUNDS.md §2 (do NOT add .nonNullable()
  /// on the list itself).
  final GraphQLFieldInput<List<String>, List<String>>
  _acknowledgedHelpTagsField = GraphQLFieldInput(
    'acknowledgedHelpTags',
    GraphQLListType(graphQLString.nonNullable()),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconClose,
    beaconExtendReview,
    beaconReopen,
    beaconCloseNow,
    evaluationSubmit,
    evaluationFinalize,
    evaluationSkip,
    evaluationDraftSave,
    evaluationDraftDelete,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconClose =>
      GraphQLObjectField(
        'beaconClose',
        gqlTypeBeaconCloseReviewResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _expectedRequiresReviewWindow.field,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.beaconClose(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
            expectedRequiresReviewWindow:
                _expectedRequiresReviewWindow.fromArgsNonNullable(args),
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconExtendReview =>
      GraphQLObjectField(
        'beaconExtendReview',
        gqlTypeBeaconCloseReviewResult.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.extendReviewWindow(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconReopen =>
      GraphQLObjectField(
        'beaconReopen',
        gqlTypeBeaconCloseReviewResult.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.reopenFromReview(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconCloseNow =>
      GraphQLObjectField(
        'beaconCloseNow',
        gqlTypeBeaconCloseReviewResult.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.closeNow(
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
          _acknowledgedHelpTagsField,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          final tags = args[_reasonTagsField.name];
          final list = tags == null
              ? <String>[]
              : List<String>.from(tags as List);
          final rawAck = args[_acknowledgedHelpTagsField.name];
          final acknowledgedHelpTags = rawAck == null
              ? null
              : List<String>.from(rawAck as List);
          return _evaluationCase.evaluationSubmit(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            evaluatorId: jwt.sub,
            evaluatedUserId: _evaluatedUserId.fromArgsNonNullable(args),
            value: args[_valueField.name]! as int,
            reasonTags: list,
            note: _note.fromArgs(args) ?? '',
            acknowledgedHelpTags: acknowledgedHelpTags,
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
