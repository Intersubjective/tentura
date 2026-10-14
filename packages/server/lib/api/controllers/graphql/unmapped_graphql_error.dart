// SPDX-License-Identifier: AGPL-3.0-only
import 'package:postgres/postgres.dart' show PgException;

import 'package:tentura_server/domain/exception.dart';

/// Message sent to clients in place of a database driver error.
const kUnmappedDatabaseErrorMessage =
    'Something went wrong on the server. Please try again.';

/// The `errors[]` entry for an exception that escaped the GraphQL resolvers
/// without being mapped to an [ExceptionBase].
///
/// Database driver errors ([PgException], including `ServerException`) carry
/// the SQL state, table, constraint and key values, e.g.
/// `23503: … ego_witness_window_witness_user_id_fkey … Key (witness_user_id)=…`.
/// Those are reported to Sentry by the caller but never sent to the client:
/// it would show them verbatim. Any other exception keeps its message, since
/// resolvers still throw plain exceptions with user-facing text.
Map<String, Object> unmappedGraphqlError(Object error) => switch (error) {
  PgException() => const UnspecifiedException(
    description: kUnmappedDatabaseErrorMessage,
  ).toMap,
  _ => {'message': error.toString()},
};
