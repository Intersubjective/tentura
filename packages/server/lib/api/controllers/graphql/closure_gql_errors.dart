import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_server/domain/exception.dart';

/// GraphQL error that keeps the domain code in `extensions.code`.
final class _CodedGraphQLError extends GraphQLExceptionError {
  _CodedGraphQLError(ExceptionBase e)
    : _extensions = e.toMap['extensions']!,
      super(e.description);

  final Object _extensions;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'extensions': _extensions,
  };
}

/// Runs a closure resolver body, mapping domain exceptions (`ClosureException`,
/// not-found) to GraphQL errors carrying the code as `extensions.code`.
Future<T> mapClosureErrors<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ExceptionBase catch (e) {
    throw GraphQLException([_CodedGraphQLError(e)]);
  }
}
