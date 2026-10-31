// A fake GraphQL server for counting how a screen load talks to the API.
//
// It answers every operation from the client's own `schema.graphql`, so a
// load keeps working when reads are folded into a batch operation or sent as
// an HTTP array: lists come back empty, objects are filled in field by field
// and [overrides] supply the values a scenario needs (status, access, ...).
//
// Responses are held back in rounds. Every request the client sends while the
// previous round is still unanswered joins the current round; once no new
// request arrives for [quietPeriod], the whole round is answered at once. A
// read that waits on another read's response therefore lands in a later
// round, so the number of rounds is the length of the longest chain of
// requests that wait on each other.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One HTTP request to a GraphQL endpoint.
typedef GraphqlRoundTripCall = ({
  int round,
  String path,
  List<String> operationNames,
});

/// Returns the value for `parentType.field`: a JSON value,
/// [GraphqlRoundTripServer.auto] to let the schema decide, or
/// [GraphqlRoundTripServer.oneRow] for a list field answered with one
/// schema-built row.
typedef GraphqlFieldOverride =
    Object? Function(String parentType, String field, String operationName);

class GraphqlRoundTripServer {
  GraphqlRoundTripServer({
    required this.viewerId,
    this.overrides,
    this.quietPeriod = const Duration(milliseconds: 60),
  });

  /// Marks "no override": the schema default is used.
  static const auto = Object();

  /// A list field answered with one row built from the schema.
  static const oneRow = Object();

  final String viewerId;
  final GraphqlFieldOverride? overrides;
  final Duration quietPeriod;

  final calls = <GraphqlRoundTripCall>[];

  int _round = 0;
  var _gate = Completer<void>();
  int _pending = 0;
  Duration _quietFor = Duration.zero;

  static _Schema? _schemaCache;
  static _Schema get _schema =>
      _schemaCache ??= _Schema(File('lib/data/gql/schema.graphql'));

  /// Number of rounds that carried at least one request.
  int get rounds => {for (final call in calls) call.round}.length;

  /// Operation names per round, for failure messages.
  String describe() {
    final byRound = <int, List<String>>{};
    for (final call in calls) {
      byRound
          .putIfAbsent(call.round, () => [])
          .add(
            call.operationNames.join('+'),
          );
    }
    return [
      for (final entry in byRound.entries)
        'round ${entry.key + 1}: ${entry.value.join(', ')}',
    ].join('\n');
  }

  http.Client get client => MockClient(_handle);

  /// Answers rounds until the client has been quiet with nothing pending for
  /// [settle], or [timeout] passes. Time is counted in [tick] steps, each
  /// one call to [wait]: real time by default; a widget test passes a
  /// `tester.pump` of [tick] so fake timers, frames and post-frame reads run
  /// too.
  Future<void> drain({
    Duration settle = const Duration(milliseconds: 400),
    Duration timeout = const Duration(seconds: 10),
    Duration tick = const Duration(milliseconds: 10),
    Future<void> Function()? wait,
  }) async {
    final step = wait ?? () => Future<void>.delayed(tick);
    var elapsed = Duration.zero;
    while (elapsed < timeout) {
      await step();
      elapsed += tick;
      _quietFor += tick;
      if (_pending > 0) {
        if (_quietFor >= quietPeriod) _releaseRound();
      } else if (_quietFor >= settle) {
        return;
      }
    }
    throw TimeoutException('GraphQL load did not settle:\n${describe()}');
  }

  void _releaseRound() {
    _round++;
    final gate = _gate;
    _gate = Completer<void>();
    gate.complete();
  }

  Future<http.Response> _handle(http.Request request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': viewerId,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body);
    final operations = [
      for (final operation in body is List ? body : [body])
        operation as Map<String, dynamic>,
    ];
    calls.add((
      round: _round,
      path: request.url.path,
      operationNames: [
        for (final operation in operations)
          operation['operationName'] as String? ?? '',
      ],
    ));
    _pending++;
    _quietFor = Duration.zero;
    final gate = _gate;
    try {
      await gate.future;
    } finally {
      _pending--;
    }
    final responses = [
      for (final operation in operations) {'data': _answer(operation)},
    ];
    return _json(body is List ? responses : responses.single);
  }

  Map<String, Object?> _answer(Map<String, dynamic> operation) {
    final document = parseString(operation['query'] as String);
    final name = operation['operationName'] as String?;
    final definition = document.definitions
        .whereType<OperationDefinitionNode>()
        .firstWhere((d) => name == null || d.name?.value == name);
    final fragments = {
      for (final f in document.definitions.whereType<FragmentDefinitionNode>())
        f.name.value: f,
    };
    final rootType = switch (definition.type) {
      OperationType.mutation => 'mutation_root',
      OperationType.subscription => 'subscription_root',
      OperationType.query => 'query_root',
    };
    return _object(rootType, definition.selectionSet, fragments, name ?? '');
  }

  Map<String, Object?> _object(
    String typeName,
    SelectionSetNode selectionSet,
    Map<String, FragmentDefinitionNode> fragments,
    String operationName,
  ) {
    final result = <String, Object?>{};
    void visit(SelectionSetNode set) {
      for (final node in set.selections) {
        if (node is FieldNode) {
          final key = node.alias?.value ?? node.name.value;
          result[key] = _field(typeName, node, fragments, operationName);
        } else if (node is InlineFragmentNode) {
          visit(node.selectionSet);
        } else if (node is FragmentSpreadNode) {
          visit(fragments[node.name.value]!.selectionSet);
        }
      }
    }

    visit(selectionSet);
    return result;
  }

  Object? _field(
    String parentType,
    FieldNode node,
    Map<String, FragmentDefinitionNode> fragments,
    String operationName,
  ) {
    final name = node.name.value;
    if (name == '__typename') return parentType;
    final override = overrides == null
        ? auto
        : overrides!(parentType, name, operationName);
    final type = _schema.fieldType(parentType, name);
    if (type is ListTypeNode) {
      if (identical(override, oneRow)) {
        return [
          _value(type.type as NamedTypeNode, node, fragments, operationName),
        ];
      }
      if (identical(override, auto)) return const <Object?>[];
      return override;
    }
    if (!identical(override, auto)) return override;
    return _value(type as NamedTypeNode, node, fragments, operationName);
  }

  Object? _value(
    NamedTypeNode type,
    FieldNode node,
    Map<String, FragmentDefinitionNode> fragments,
    String operationName,
  ) {
    final selectionSet = node.selectionSet;
    if (selectionSet != null) {
      return _object(type.name.value, selectionSet, fragments, operationName);
    }
    return _scalar(type.name.value, node.name.value, nonNull: type.isNonNull);
  }

  Object? _scalar(String typeName, String field, {required bool nonNull}) {
    final enumValues = _schema.enumValues(typeName);
    if (enumValues != null) return nonNull ? enumValues.first : null;
    final looksLikeTime =
        field.endsWith('_at') ||
        field.endsWith('At') ||
        field == 'resume_on' ||
        typeName == 'timestamptz' ||
        typeName == 'date' ||
        typeName == 'v2_Date';
    if (looksLikeTime) return nonNull ? '2026-10-20T12:00:00Z' : null;
    return switch (typeName) {
      'Int' || 'smallint' || 'bigint' => 0,
      'Float' || 'float8' || 'numeric' => 0.0,
      'Boolean' => false,
      'String' when field == 'id' || field.endsWith('Id') => 'X$field',
      'String' when field.endsWith('Json') => '[]',
      _ => nonNull ? '' : null,
    };
  }

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

class _Schema {
  _Schema(File file) {
    final document = parseString(file.readAsStringSync());
    for (final definition in document.definitions) {
      switch (definition) {
        case ObjectTypeDefinitionNode(:final name, :final fields):
          _fields[name.value] = {for (final f in fields) f.name.value: f.type};
        case InterfaceTypeDefinitionNode(:final name, :final fields):
          _fields[name.value] = {for (final f in fields) f.name.value: f.type};
        case EnumTypeDefinitionNode(:final name, :final values):
          _enums[name.value] = [for (final v in values) v.name.value];
        default:
      }
    }
  }

  final _fields = <String, Map<String, TypeNode>>{};
  final _enums = <String, List<String>>{};

  TypeNode fieldType(String parentType, String field) {
    final type = _fields[parentType]?[field];
    if (type == null) {
      throw StateError('schema.graphql has no field $parentType.$field');
    }
    return type;
  }

  List<String>? enumValues(String typeName) => _enums[typeName];
}
