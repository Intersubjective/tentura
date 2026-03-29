import 'package:collection/collection.dart' show IterableExtension;
import 'package:graphql_parser2/graphql_parser2.dart'
    show ArgumentContext, SelectionContext;
import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';

import 'custom_types.dart';
import 'mutation/_mutations_all.dart';
import 'query/_queries_all.dart';

export 'package:graphql_schema2/graphql_schema2.dart';

GraphQL get graphqlSchema => _NullSafeGraphQL(
  GraphQLSchema(
    queryType: GraphQLObjectType('Query', 'Query root')
      ..fields.addAll(queriesAll),
    mutationType: GraphQLObjectType('Mutation', 'Mutation root')
      ..fields.addAll(mutationsAll),
  ),
  customTypes: customTypes,
);

/// Workaround for graphql_server2 bug: `coerceArgumentValues` passes null
/// values to `argumentType.validate` even for nullable types. Scalar
/// `validate` methods (e.g. `graphQLString`) reject null, which violates the
/// GraphQL spec that nullable arguments must accept null.
class _NullSafeGraphQL extends GraphQL {
  _NullSafeGraphQL(super.schema, {super.customTypes});

  @override
  Map<String, dynamic> coerceArgumentValues(
    GraphQLObjectType objectType,
    SelectionContext field,
    Map<String?, dynamic> variableValues,
  ) {
    final coercedValues = <String, dynamic>{};
    final argumentValues = field.field?.arguments;
    final fieldName =
        field.field?.fieldName.alias?.name ?? field.field?.fieldName.name;
    final desiredField = objectType.fields.firstWhere(
      (f) => f.name == fieldName,
      orElse:
          () => throw FormatException(
            '${objectType.name} has no field named "$fieldName".',
          ),
    );
    final argumentDefinitions = desiredField.inputs;

    for (final argumentDefinition in argumentDefinitions) {
      final argumentName = argumentDefinition.name;
      final argumentType = argumentDefinition.type;
      final defaultValue = argumentDefinition.defaultValue;

      final argumentValue = argumentValues?.firstWhereOrNull(
        (ArgumentContext a) => a.name == argumentName,
      );

      if (argumentValue == null) {
        if (defaultValue != null || argumentDefinition.defaultsToNull) {
          coercedValues[argumentName] = defaultValue;
        } else if (argumentType is GraphQLNonNullableType) {
          throw GraphQLException.fromMessage(
            'Missing value for argument "$argumentName" of field "$fieldName".',
          );
        } else {
          continue;
        }
      } else {
        final inputValue = argumentValue.value.computeValue(
          variableValues as Map<String, dynamic>,
        );

        // FIX: per GraphQL spec, nullable arguments accept null without
        // validation.  The base class skips this check, causing scalar
        // validate() to reject null for nullable types.
        if (inputValue == null && argumentType is! GraphQLNonNullableType) {
          coercedValues[argumentName] = null;
          continue;
        }

        try {
          final validation = argumentType.validate(argumentName, inputValue);

          if (!validation.successful) {
            final errors = <GraphQLExceptionError>[
              GraphQLExceptionError(
                'Type coercion error for value of argument "$argumentName" of field "$fieldName". ($inputValue)',
                locations: [
                  GraphExceptionErrorLocation.fromSourceLocation(
                    argumentValue.value.span!.start,
                  ),
                ],
              ),
            ];

            for (final error in validation.errors) {
              final err = argumentValue.value.span?.start;
              final locations = <GraphExceptionErrorLocation>[];
              if (err != null) {
                locations.add(
                  GraphExceptionErrorLocation.fromSourceLocation(err),
                );
              }
              errors.add(GraphQLExceptionError(error, locations: locations));
            }

            throw GraphQLException(errors);
          } else {
            final coercedValue = argumentType.deserialize(inputValue);

            coercedValues[argumentName] = coercedValue;
          }
          // ignore: avoid_catching_errors -- mirrors graphql_server2 internals
        } on TypeError catch (e) {
          final err = argumentValue.value.span?.start;
          final locations = <GraphExceptionErrorLocation>[];
          if (err != null) {
            locations
                .add(GraphExceptionErrorLocation.fromSourceLocation(err));
          }

          throw GraphQLException(<GraphQLExceptionError>[
            GraphQLExceptionError(
              'Type coercion error for value of argument "$argumentName" of field "$fieldName". [$inputValue]',
              locations: locations,
            ),
            GraphQLExceptionError(e.toString(), locations: locations),
          ]);
        }
      }
    }

    return coercedValues;
  }
}
