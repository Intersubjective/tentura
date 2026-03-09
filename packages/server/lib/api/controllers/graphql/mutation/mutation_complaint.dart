import 'package:tentura_server/domain/use_case/complaint_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationComplaint extends GqlNodeBase {
  MutationComplaint([ComplaintCase? complaintCase])
    : _complaintCase = complaintCase ?? GetIt.I<ComplaintCase>();

  final ComplaintCase _complaintCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
  ];

  GraphQLObjectField<dynamic, dynamic> get create => GraphQLObjectField(
    'complaintCreate',
    graphQLBoolean.nonNullable(),
    arguments: [
      InputFieldId.field,
      _typeInput.field,
      _emailInput.field,
      _detailsInput.field,
    ],
    resolve: (_, args) => _complaintCase.create(
      userId: getCredentials(args).sub,
      id: InputFieldId.fromArgsNonNullable(args),
      type: _typeInput.fromArgsNonNullable(args),
      email: _emailInput.fromArgsNonNullable(args),
      details: _detailsInput.fromArgsNonNullable(args),
    ),
  );

  static final _typeInput = InputFieldString(fieldName: 'type');

  static final _emailInput = InputFieldString(fieldName: 'email');

  static final _detailsInput = InputFieldString(fieldName: 'details');
}
