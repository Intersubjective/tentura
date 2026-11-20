import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

/// SQL parity for the user-role beacon reads in the bud privacy scenario.
final class BeaconMetadataReader {
  BeaconMetadataReader._(
    this._connection,
    this._fields,
    this._predicate,
    this.privacyViolations,
  );

  static Future<BeaconMetadataReader> fromRepo(Connection connection) async {
    final file = File('../../hasura/metadata.json');
    if (!file.existsSync()) {
      throw StateError('Hasura permission source is missing: ${file.path}');
    }
    final metadata = jsonDecode(file.readAsStringSync());
    final sources = switch (metadata) {
      {'metadata': {'sources': final List<Object?> sources}} => sources,
      _ => throw StateError('Invalid Hasura metadata in ${file.path}'),
    };
    for (final source in sources) {
      if (source is! Map<String, Object?> ||
          source['tables'] is! List<Object?>) {
        continue;
      }
      final tables = {
        for (final table in _objects(source['tables']))
          ?_tableName(table['table']): table,
      };
      final beacon = tables[_beacon];
      if (beacon?['computed_fields'] case final List<Object?> definitions) {
        if (_userSelect(beacon) case {
          'columns': final List<Object?> columns,
          'computed_fields': final List<Object?> computed,
          'filter': final Map<String, Object?> filter,
        }) {
          final fields = _readFields(columns, computed, definitions, file.path);
          final violations = await _privacyViolations(connection, tables);
          return BeaconMetadataReader._(
            connection,
            fields,
            _readFilter(filter, fields, file.path, violations),
            violations,
          );
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
  final List<String> privacyViolations;

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

typedef _TableName = ({String schema, String name});

const _beacon = (schema: 'public', name: 'beacon');
const _contentWall = 'can_read_content';

_TableName? _tableName(Object? value) => switch (value) {
  {'schema': final String schema, 'name': final String name} => (
    schema: schema,
    name: name,
  ),
  _ => null,
};

Iterable<Map<String, Object?>> _objects(Object? value) => switch (value) {
  final List<Object?> list => list.whereType<Map<String, Object?>>(),
  _ => const [],
};

Map<String, Object?>? _userSelect(Map<String, Object?>? table) {
  for (final entry in _objects(table?['select_permissions'])) {
    if (entry case {
      'role': 'user',
      'permission': final Map<String, Object?> permission,
    }) {
      return permission;
    }
  }
  return null;
}

bool _requires(Object? filter, bool Function(Map<String, Object?>) predicate) {
  if (filter is! Map<String, Object?>) return false;
  if (predicate(filter)) return true;
  if (filter['_and'] case final List<Object?> terms
      when terms.any((term) => _requires(term, predicate))) {
    return true;
  }
  return switch (filter['_or']) {
    final List<Object?> terms =>
      terms.isNotEmpty && terms.every((term) => _requires(term, predicate)),
    _ => false,
  };
}

bool _requiresTrue(Object? filter, String field) => _requires(
  filter,
  (term) => switch (term[field]) {
    {'_eq': true} => true,
    _ => false,
  },
);

typedef _ForeignKey = ({_TableName table, String columns});

Future<Map<_ForeignKey, Set<_TableName>>> _foreignKeys(Connection pg) async {
  // Hasura's shorthand object relationships name only the source columns.
  final rows = await pg.execute('''
SELECT src_ns.nspname, src.relname, dst_ns.nspname, dst.relname,
       json_agg(col.attname ORDER BY col.attname COLLATE "C")::text
FROM pg_constraint AS fk
JOIN pg_class AS src ON src.oid = fk.conrelid
JOIN pg_namespace AS src_ns ON src_ns.oid = src.relnamespace
JOIN pg_class AS dst ON dst.oid = fk.confrelid
JOIN pg_namespace AS dst_ns ON dst_ns.oid = dst.relnamespace
JOIN pg_attribute AS col ON col.attrelid = src.oid AND col.attnum = ANY(fk.conkey)
WHERE fk.contype = 'f'
GROUP BY fk.oid, src_ns.nspname, src.relname, dst_ns.nspname, dst.relname
''');
  final keys = <_ForeignKey, Set<_TableName>>{};
  for (final row in rows) {
    if (row.toList() case [
      final String sourceSchema,
      final String source,
      final String targetSchema,
      final String target,
      final String columns,
    ]) {
      final key = (
        table: (schema: sourceSchema, name: source),
        columns: jsonEncode(jsonDecode(columns)),
      );
      (keys[key] ??= {}).add((schema: targetSchema, name: target));
    }
  }
  return keys;
}

_TableName? _relationshipTarget(
  Map<String, Object?> relationship,
  _TableName source,
  Map<_ForeignKey, Set<_TableName>> foreignKeys,
) {
  final using = relationship['using'];
  if (using case {'manual_configuration': {'remote_table': final table}}) {
    return _tableName(table);
  }
  if (using case {'foreign_key_constraint_on': final key}) {
    final columns = switch (key) {
      final String column => [column],
      final List<Object?> columns => _names(
        columns,
        'foreign key',
      ).toList()..sort(),
      _ => null,
    };
    if (columns != null) {
      final targets =
          foreignKeys[(table: source, columns: jsonEncode(columns))];
      return targets?.singleOrNull;
    }
    if (key case {'table': final table}) return _tableName(table);
  }
  return null;
}

// These rows have their own visibility policies. Traversal still checks all
// relationships from them, and new aggregates need their own content wall.
const _ancillaryRows = {
  'beacon_admitted_helper',
  'beacon_archived',
  'beacon_forward_edge',
  'beacon_help_offer',
  'beacon_help_offer_coordination',
  'beacon_participant',
  'beacon_pinned',
  'beacon_room_state',
  'beacon_steward',
  'image',
  'post_draft_attachment',
  'user',
  'user_availability',
  'user_presence',
  'vote_beacon',
  'vote_user',
};

Future<List<String>> _privacyViolations(
  Connection connection,
  Map<_TableName, Map<String, Object?>> tables,
) async {
  final keys = await _foreignKeys(connection);
  final objectRelationships = {
    for (final entry in tables.entries)
      entry.key: {
        for (final link in _objects(entry.value['object_relationships']))
          if (link['name'] case final String name)
            name: _relationshipTarget(link, entry.key, keys),
      },
  };

  bool requiresBeaconField(_TableName table, Object? filter, String field) {
    final links = objectRelationships[table];
    final beaconLinks = links?.entries.where((link) => link.value == _beacon);
    return beaconLinks != null &&
        beaconLinks.isNotEmpty &&
        beaconLinks.every(
          (link) =>
              _requires(filter, (term) => _requiresTrue(term[link.key], field)),
        );
  }

  bool contentProtected(_TableName table, Object? filter) =>
      _requiresTrue(filter, _contentWall) ||
      (table != _beacon && requiresBeaconField(table, filter, _contentWall));

  bool aggregateProtected(_TableName table, Object? filter) =>
      contentProtected(table, filter) ||
      switch (table) {
        (schema: 'public', name: 'beacon_admitted_helper') =>
          requiresBeaconField(table, filter, 'can_read_admitted_helpers'),
        (schema: 'public', name: 'beacon_help_offer') => requiresBeaconField(
          table,
          filter,
          'can_read_involvement',
        ),
        _ => false,
      };

  final violations = <String>[];
  final root = tables[_beacon];
  final rootSelect = _userSelect(root);
  if (rootSelect?['allow_aggregations'] == true &&
      !contentProtected(_beacon, rootSelect?['filter'])) {
    final configuration = root?['configuration'];
    final name = switch (configuration) {
      {'custom_root_fields': {'select_aggregate': final String name}} ||
      {
        'custom_root_fields': {'select_aggregate': {'name': final String name}},
      } => name,
      {'custom_name': final String name} => '${name}_aggregate',
      _ => 'beacon_aggregate',
    };
    violations.add(name);
  }

  final visited = {_beacon};
  final pending = Queue<(_TableName, String)>()..add((_beacon, 'beacon'));
  while (pending.isNotEmpty) {
    final (table, path) = pending.removeFirst();
    final metadata = tables[table];
    final links = objectRelationships[table];
    for (final remote in _objects(metadata?['remote_relationships'])) {
      violations.add(
        '$path.${remote['name']} (unsupported remote relationship)',
      );
    }
    for (final (array, relationships) in [
      (false, _objects(metadata?['object_relationships'])),
      (true, _objects(metadata?['array_relationships'])),
    ]) {
      for (final relationship in relationships) {
        final name = relationship['name'];
        final field = '$path.$name';
        final destination = array
            ? _relationshipTarget(relationship, table, keys)
            : links?[name];
        if (destination == null || !tables.containsKey(destination)) {
          violations.add('$field (unresolved relationship)');
          continue;
        }
        final permission = _userSelect(tables[destination]);
        if (permission == null) continue;
        final filter = permission['filter'];
        final ancillary =
            destination.schema == 'public' &&
            _ancillaryRows.contains(destination.name);
        if (!ancillary && !contentProtected(destination, filter)) {
          violations.add(field);
        }
        if (array &&
            permission['allow_aggregations'] == true &&
            !aggregateProtected(destination, filter)) {
          violations.add('${field}_aggregate');
        }
        if (visited.add(destination)) pending.add((destination, field));
      }
    }
  }
  return List.unmodifiable(violations);
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
  List<String> violations,
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
      'Unsupported user-role beacon filter in $path: ${entry.key}: ${entry.value}'
      '\n${violations.join('\n')}',
    );
  }
  return conditions.isEmpty ? 'TRUE' : conditions.join(' AND ');
}
