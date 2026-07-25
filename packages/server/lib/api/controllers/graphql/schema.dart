import 'package:collection/collection.dart' show IterableExtension;
import 'package:graphql_parser2/graphql_parser2.dart'
    show SelectionContext, TypeContext;
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

/// Resolves [name] against [types], accepting Hasura-stitched `v2_*` aliases
/// used by direct-to-V2 client documents (`v2_Upload` → `Upload`).
///
/// Exact match wins so intentionally prefixed server types
/// (e.g. `v2_PersonTopCapabilities`) stay unchanged.
GraphQLType? resolveStitchedV2Type(
  String name,
  Iterable<GraphQLType<dynamic, dynamic>> types,
) {
  final exact = types.firstWhereOrNull((t) => t.name == name);
  if (exact != null) return exact;
  if (name.startsWith('v2_') && name.length > 3) {
    final bare = name.substring(3);
    return types.firstWhereOrNull((t) => t.name == bare);
  }
  return null;
}

/// Workaround for graphql_server2 bug: `coerceArgumentValues` passes null
/// values to `argumentType.validate` even for nullable types. Scalar
/// `validate` methods (e.g. `graphQLString`) reject null, which violates the
/// GraphQL spec that nullable arguments must accept null.
///
/// Also resolves Hasura-stitched `v2_*` names in **direct-to-V2** client
/// documents to the unprefixed server types (`v2_Upload` → `Upload`,
/// `v2_Coordinates` → `Coordinates`). Server types stay unprefixed so Hasura
/// remote-schema stitching still produces a single `v2_` layer — do not
/// rename those inputs to `v2_*` on the server.
class _NullSafeGraphQL extends GraphQL {
  _NullSafeGraphQL(super.schema, {super.customTypes});

  /// Prefer stock lookup (keeps introspection types like `__Type`). Only when
  /// that fails for a Hasura-stitched `v2_*` name, fall back to the bare
  /// server type (`v2_Upload` → `Upload`).
  @override
  GraphQLType convertType(
    TypeContext ctx, {
    bool usePolymorphicName = false,
    GraphQLObjectType? parent,
  }) {
    try {
      return super.convertType(
        ctx,
        usePolymorphicName: usePolymorphicName,
        parent: parent,
      );
      // ignore: avoid_catching_errors -- graphql_server2 signals unknown types via ArgumentError
    } on ArgumentError catch (_) {
      final name = ctx.typeName?.name;
      if (name == null || !name.startsWith('v2_') || name.length <= 3) {
        rethrow;
      }
      final resolved = resolveStitchedV2Type(name, customTypes);
      if (resolved != null) return resolved;
      rethrow;
    }
  }

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
        (a) => a.name == argumentName,
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
