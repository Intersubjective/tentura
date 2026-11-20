import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

/// SQL parity for the user-role beacon reads in the bud privacy scenario.
final class BeaconMetadataReader {
  BeaconMetadataReader._(this._connection, this._fields, this._predicate);

  factory BeaconMetadataReader.fromRepo(Connection connection) {
    final file = File('../../hasura/metadata.json');
    if (!file.existsSync()) {
      throw StateError('Hasura permission source is missing: ${file.path}');
    }
    final metadata = jsonDecode(file.readAsStringSync());
    final tables = switch (metadata) {
      {'metadata': {'sources': final List<Object?> sources}} => [
        for (final source in sources)
          if (source case {'tables': final List<Object?> tables}) ...tables,
      ],
      _ => throw StateError('Invalid Hasura metadata in ${file.path}'),
    };
    for (final table in tables) {
      if (table case {
        'table': {'schema': 'public', 'name': 'beacon'},
        'select_permissions': final List<Object?> permissions,
        'computed_fields': final List<Object?> computedFields,
      }) {
        for (final select in permissions) {
          if (select case {
            'role': 'user',
            'permission': {
              'columns': final List<Object?> columns,
              'computed_fields': final List<Object?> computed,
              'filter': final Map<String, Object?> filter,
            },
          }) {
            final fields = _readFields(
              columns,
              computed,
              computedFields,
              file.path,
            );
            return BeaconMetadataReader._(
              connection,
              fields,
              _readFilter(filter, fields, file.path),
            );
          }
        }
      }
    }
    throw StateError(
      'Missing user-role public.beacon permissions in ${file.path}',
    );
  }

  final Connection _connection;
  final Map<String, String> _fields;
  final String _predicate;

  Iterable<String> get fields => _fields.keys;

  Future<List<Map<String, Object?>>> read(
    String viewer,
    List<String> ids,
    List<String> projection,
  ) async {
    final selections = projection.map((field) {
      final expression = _fields[field];
      if (expression == null) {
        throw StateError('User role cannot select $field');
      }
      return '$expression AS ${_identifier(field)}';
    });
    final rows = await _connection.execute(
      Sql.named('''
SELECT ${selections.join(', ')}
FROM public.beacon AS beacon
CROSS JOIN (SELECT CAST(@session AS json) AS session) AS viewer
WHERE beacon.id = ANY(CAST(@ids AS text[])) AND ($_predicate)
'''),
      parameters: {
        'ids': ids,
        'session': jsonEncode({
          'x-hasura-role': 'user',
          'x-hasura-user-id': viewer,
        }),
      },
    );
    return [for (final row in rows) row.toColumnMap()];
  }
}

String _identifier(String name) => '"${name.replaceAll('"', '""')}"';

Set<String> _names(List<Object?> fields, String path) => {
  for (final field in fields)
    switch (field) {
      final String name => name,
      _ => throw StateError('Invalid beacon permission field in $path: $field'),
    },
};

Map<String, String> _readFields(
  List<Object?> columns,
  List<Object?> computed,
  List<Object?> definitions,
  String path,
) {
  final fields = {
    for (final field in _names(columns, path))
      field: 'beacon.${_identifier(field)}',
  };
  final permittedComputed = _names(computed, path);
  for (final field in definitions) {
    if (field case {
      'name': final String name,
      'definition': {
        'function': {
          'schema': final String schema,
          'name': final String function,
        },
        'table_argument': final String row,
        'session_argument': final String session,
      },
    } when permittedComputed.contains(name)) {
      fields[name] =
          '${_identifier(schema)}.${_identifier(function)}'
          '(${_identifier(row)} => beacon, '
          '${_identifier(session)} => viewer.session)';
    }
  }
  if (!fields.keys.toSet().containsAll(permittedComputed)) {
    throw StateError('Unsupported user-role beacon computed field in $path');
  }
  return fields;
}

String _readFilter(
  Map<String, Object?> filter,
  Map<String, String> fields,
  String path,
) {
  // Multiple fields form a conjunction. Reject operators this reader cannot
  // evaluate so a metadata change cannot silently bypass the permission.
  final conditions = <String>[];
  for (final entry in filter.entries) {
    final expression = fields[entry.key];
    if (entry.value case final Map<String, Object?> operators
        when expression != null && operators.length == 1) {
      if (operators['_eq'] case final bool value) {
        conditions.add('$expression = ${value ? 'TRUE' : 'FALSE'}');
        continue;
      }
    }
    throw StateError(
      'Unsupported user-role beacon filter in $path: ${entry.key}: ${entry.value}',
    );
  }
  return conditions.isEmpty ? 'TRUE' : conditions.join(' AND ');
}
