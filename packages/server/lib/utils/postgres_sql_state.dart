import 'package:postgres/postgres.dart' show ServerException;

/// The Postgres SQLSTATE of [error] (for example `23514`) when the database
/// raised it, else null. Safe to log: unlike the error's text and detail
/// ("Failing row contains (…)"), the code carries no row data.
String? postgresSqlState(Object error) =>
    error is ServerException ? error.code : null;
