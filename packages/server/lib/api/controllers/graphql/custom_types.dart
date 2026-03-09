import 'package:graphql_schema2/graphql_schema2.dart';

import 'input/_input_types.dart';

List<GraphQLType<dynamic, dynamic>> get customTypes => [
  InputFieldCoordinates.type,
  InputFieldPolling.type,
  InputFieldUpload.type,
  gqlTypeAuthResponse,
  gqlTypeInvitation,
  gqlTypeProfile,
  gqlTypeBeacon,
];

final gqlTypeAuthResponse = GraphQLObjectType('AuthResponse', null)
  ..fields.addAll([
    field('subject', graphQLString.nonNullable()),
    field('expires_in', graphQLInt.nonNullable()),
    field('token_type', graphQLString.nonNullable()),
    field('access_token', graphQLString.nonNullable()),
    field('refresh_token', graphQLString),
  ]);

final gqlTypeBeacon = GraphQLObjectType('Beacon', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
  ]);

final gqlTypeProfile = GraphQLObjectType('User', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
  ]);

final gqlTypeInvitation = GraphQLObjectType('Invitation', null)
  ..fields.addAll([
    field('id', graphQLString.nonNullable()),
    field('issuer_id', graphQLString.nonNullable()),
    field('invited_id', graphQLString),
    field('created_at', graphQLString.nonNullable()),
    field('updated_at', graphQLString.nonNullable()),
  ]);
