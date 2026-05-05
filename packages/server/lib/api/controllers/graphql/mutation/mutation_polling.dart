import 'package:tentura_server/domain/use_case/polling_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationPolling extends GqlNodeBase {
  MutationPolling({PollingCase? pollingCase})
    : _pollingCase = pollingCase ?? GetIt.I<PollingCase>();

  final PollingCase _pollingCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [pollingAct];

  GraphQLObjectField<dynamic, dynamic> get pollingAct => GraphQLObjectField(
    'pollingAct',
    graphQLBoolean.nonNullable(),
    arguments: [
      _pollingIdInput.field,
      _variantIdsInput.field,
      _scoreInput.fieldNullable,
    ],
    resolve: (_, args) => _pollingCase.create(
      authorId: getCredentials(args).sub,
      pollingId: _pollingIdInput.fromArgsNonNullable(args),
      variantIds: _variantIdsInput.fromArgsNonNullable(args),
      score: _scoreInput.fromArgs(args),
    ),
  );

  static final _pollingIdInput = InputFieldString(fieldName: 'pollingId');

  static final _variantIdsInput = InputFieldStringList(fieldName: 'variantIds');

  static final _scoreInput = InputFieldInt(fieldName: 'score');
}
