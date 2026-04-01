import 'package:tentura_server/domain/use_case/evaluation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryEvaluation extends GqlNodeBase {
  QueryEvaluation({EvaluationCase? evaluationCase})
    : _evaluationCase = evaluationCase ?? GetIt.I<EvaluationCase>();

  final EvaluationCase _evaluationCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    evaluationParticipants,
    reviewWindowStatus,
    evaluationSummary,
  ];

  GraphQLObjectField<dynamic, dynamic> get evaluationParticipants =>
      GraphQLObjectField(
        'evaluationParticipants',
        GraphQLListType(gqlTypeEvaluationParticipant.nonNullable()),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.evaluationParticipants(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            evaluatorId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get reviewWindowStatus =>
      GraphQLObjectField(
        'reviewWindowStatus',
        gqlTypeReviewWindowStatus.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.reviewWindowStatus(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get evaluationSummary =>
      GraphQLObjectField(
        'evaluationSummary',
        gqlTypeEvaluationSummary.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _evaluationCase.evaluationSummary(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            userId: jwt.sub,
          );
        },
      );
}
