// SPDX-License-Identifier: AGPL-3.0-only
import 'package:tentura_server/domain/exception.dart';

/// Message sent to clients in place of an unmapped server error.
const kUnmappedDatabaseErrorMessage =
    'Something went wrong on the server. Please try again.';

/// The `errors[]` entry for an exception that escaped the GraphQL resolvers
/// without being mapped to an [ExceptionBase].
///
/// Every such exception is internal: database driver errors (`PgException`,
/// with SQL state, table, constraint and key values), pool
/// `TimeoutException`s, admission `StateError`s, drift errors and plain
/// `Exception`s thrown from `domain/` and `api/`. User-facing errors are
/// [ExceptionBase]s and never reach this catch-all. The caller reports
/// [error] to Sentry; the client only gets the generic `1000` entry.
Map<String, Object> unmappedGraphqlError(Object error) =>
    const UnspecifiedException(
      description: kUnmappedDatabaseErrorMessage,
    ).toMap;
