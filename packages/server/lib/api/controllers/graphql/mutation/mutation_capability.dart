import 'package:tentura_server/domain/use_case/capability_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCapability extends GqlNodeBase {
  MutationCapability({CapabilityCase? capabilityCase})
    : _capabilityCase = capabilityCase ?? GetIt.I<CapabilityCase>();

  final CapabilityCase _capabilityCase;

  static final _subjectUserId = InputFieldString(fieldName: 'subjectUserId');

  static final _slugs = GraphQLFieldInput(
    'slugs',
    GraphQLListType(graphQLString.nonNullable()),
  );

  static List<String> _slugsFromArgs(Map<String, dynamic> args) =>
      List<String>.from(args['slugs']! as List);

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    capabilityPrivateLabelSet,
    capabilitySetViewerVisible,
  ];

  GraphQLObjectField<dynamic, dynamic> get capabilityPrivateLabelSet =>
      GraphQLObjectField(
        'capabilityPrivateLabelSet',
        graphQLBoolean.nonNullable(),
        arguments: [_subjectUserId.field, _slugs],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _capabilityCase.upsertPrivateLabel(
            observerId: jwt.sub,
            subjectId: _subjectUserId.fromArgsNonNullable(args),
            slugs: _slugsFromArgs(args),
          );
          return true;
        },
      );

  GraphQLObjectField<dynamic, dynamic> get capabilitySetViewerVisible =>
      GraphQLObjectField(
        'capabilitySetViewerVisible',
        graphQLBoolean.nonNullable(),
        arguments: [_subjectUserId.field, _slugs],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _capabilityCase.setViewerVisible(
            observerId: jwt.sub,
            subjectId: _subjectUserId.fromArgsNonNullable(args),
            slugs: _slugsFromArgs(args),
          );
          return true;
        },
      );
}
