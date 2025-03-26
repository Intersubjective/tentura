import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_server/consts.dart';

const kGlobalInputQueryContext = 'queryContext';
const kGlobalInputQueryImage = 'queryImage';
const kGlobalInputQueryJwt = kContextJwtKey;

const kInputTypeIdFieldName = 'id';
final gqlInputTypeId = GraphQLFieldInput(
  kInputTypeIdFieldName,
  graphQLNonEmptyString.nonNullable(),
);

const kInputTypeTitleFieldName = 'title';
final gqlInputTypeTitle = GraphQLFieldInput(
  kInputTypeTitleFieldName,
  graphQLString,
  defaultsToNull: true,
);

const kInputTypeQueryContext = 'context';
final gqlInputTypeQueryContext = GraphQLFieldInput(
  kInputTypeQueryContext,
  graphQLString,
  defaultsToNull: true,
);

const kInputTypeDescriptionFieldName = 'description';
final gqlInputTypeDescription = GraphQLFieldInput(
  kInputTypeDescriptionFieldName,
  graphQLString,
  defaultsToNull: true,
);

const kInputTypeAuthRequestToken = 'authRequestToken';
final gqlInputTypeAuthRequestToken = GraphQLFieldInput(
  kInputTypeAuthRequestToken,
  graphQLNonEmptyString.nonNullable(),
);

const kInputTypeDropImageFieldName = 'dropImage';
final gqlInputTypeDropImage = GraphQLFieldInput(
  kInputTypeDropImageFieldName,
  graphQLBoolean,
);
