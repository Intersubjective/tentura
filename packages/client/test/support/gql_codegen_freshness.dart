import 'dart:io';

// gql is a transitive dependency (ferry); the generated code imports it too.
// ignore: depend_on_referenced_packages
import 'package:gql/ast.dart';
// gql is a transitive dependency (ferry); the generated code imports it too.
// ignore: depend_on_referenced_packages
import 'package:gql/language.dart';

/// tentura-sae: content-based freshness check for the generated
/// `_g/<document>.{ast,data,req,var}.gql.dart` outputs of the `.graphql`
/// documents in [gqlDir], checked against [schema]. Returns one problem
/// string per stale or missing output (naming the document / file); empty
/// when everything is current. Must not depend on file mtimes.
///
/// Contract pinned by `gql_codegen_freshness_test.dart`.
List<String> findStaleGqlCodegen({
  required Directory gqlDir,
  required File schema,
  required Iterable<String> documents,
}) {
  final problems = <String>[];
  final schemaDoc = _parse(schema, problems);
  for (final name in documents) {
    final source = File('${gqlDir.path}/$name.graphql');
    if (!source.existsSync()) {
      problems.add('$name: ${source.path} is missing');
      continue;
    }
    final document = _parse(source, problems);
    if (document == null) {
      continue;
    }
    final operations = document.definitions
        .whereType<OperationDefinitionNode>()
        .toList();
    final generated = <String, String>{};
    for (final suffix in _suffixes) {
      final file = File('${gqlDir.path}/_g/$name.$suffix.gql.dart');
      if (file.existsSync()) {
        generated[suffix] = file.readAsStringSync();
      } else {
        problems.add('$name: ${file.path} is missing: run build_runner');
      }
    }
    if (generated.length != _suffixes.length) {
      continue;
    }

    final tokens = _AstTokens();
    final fields = <String>{};
    final variables = <String>{};
    for (final op in operations) {
      tokens.visitOperation(op);
      _collectFields(op.selectionSet, fields);
      variables.addAll(op.variableDefinitions.map((v) => v.variable.name.value));
    }

    void stale(String suffix, String what) =>
        problems.add('$name: $name.$suffix.gql.dart is stale: $what');

    final astTokens = _tokenRe
        .allMatches(generated['ast']!)
        .map((m) => m[1] ?? 'nonNull:${m[2]}')
        .toList();
    if (astTokens.join('\n') != tokens.values.join('\n')) {
      stale('ast', 'does not match $name.graphql');
    }
    if (!_sameSet(_getters(generated['var']!), variables)) {
      stale('var', 'variables differ from $name.graphql');
    }
    if (!_sameSet(_getters(generated['data']!), {...fields, 'G__typename'})) {
      stale('data', 'selected fields differ from $name.graphql');
    }
    for (final op in operations) {
      if (!generated['req']!.contains("operationName: '${op.name?.value}'")) {
        stale('req', 'operation name differs from $name.graphql');
      }
    }
    if (schemaDoc != null) {
      problems.addAll(_schemaProblems(name, operations, schemaDoc));
    }
  }
  return problems;
}

const _suffixes = ['ast', 'data', 'req', 'var'];

/// A name in the generated AST, or the `isNonNull` flag of a type.
final _tokenRe = RegExp(r"NameNode\(value: '([^']*)'\)|isNonNull: (true|false)");

final _getterRe = RegExp(r'\bget (\w+);');

DocumentNode? _parse(File file, List<String> problems) {
  if (!file.existsSync()) {
    problems.add('${file.path} is missing');
    return null;
  }
  try {
    return parseString(file.readAsStringSync());
  } on Object catch (e) {
    problems.add('${file.path} does not parse: $e');
    return null;
  }
}

Set<String> _getters(String source) =>
    _getterRe.allMatches(source).map((m) => m[1]!).toSet();

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Response keys (alias, else name) of every selected field, at any depth.
void _collectFields(SelectionSetNode? set, Set<String> into) {
  for (final selection in set?.selections ?? const <SelectionNode>[]) {
    if (selection is FieldNode) {
      into.add((selection.alias ?? selection.name).value);
      _collectFields(selection.selectionSet, into);
    } else if (selection is InlineFragmentNode) {
      _collectFields(selection.selectionSet, into);
    }
  }
  into.remove('__typename');
}

/// Names and non-null flags of an operation in the order the generated
/// `*.ast.gql.dart` spells them out.
class _AstTokens {
  final values = <String>[];

  void visitOperation(OperationDefinitionNode op) {
    _name(op.name);
    for (final v in op.variableDefinitions) {
      _name(v.variable.name);
      _type(v.type);
    }
    _selections(op.selectionSet);
  }

  void _name(NameNode? name) {
    if (name != null) {
      values.add(name.value);
    }
  }

  void _type(TypeNode type) {
    if (type is ListTypeNode) {
      _type(type.type);
    } else if (type is NamedTypeNode) {
      _name(type.name);
    }
    values.add('nonNull:${type.isNonNull}');
  }

  void _selections(SelectionSetNode? set) {
    for (final selection in set?.selections ?? const <SelectionNode>[]) {
      if (selection is! FieldNode) {
        continue;
      }
      if (selection.name.value == '__typename') {
        continue;
      }
      _name(selection.name);
      _name(selection.alias);
      for (final arg in selection.arguments) {
        _name(arg.name);
        final value = arg.value;
        if (value is VariableNode) {
          _name(value.name);
        }
      }
      _selections(selection.selectionSet);
    }
  }
}

/// Root field + argument names the documents use must exist in the schema.
List<String> _schemaProblems(
  String name,
  List<OperationDefinitionNode> operations,
  DocumentNode schema,
) {
  final rootTypes = <OperationType, String>{
    OperationType.query: 'Query',
    OperationType.mutation: 'Mutation',
    OperationType.subscription: 'Subscription',
  };
  for (final def in schema.definitions.whereType<SchemaDefinitionNode>()) {
    for (final t in def.operationTypes) {
      rootTypes[t.operation] = t.type.name.value;
    }
  }
  final problems = <String>[];
  for (final op in operations) {
    final rootName = rootTypes[op.type]!;
    final rootFields = <String, FieldDefinitionNode>{
      for (final def in schema.definitions)
        if (def is ObjectTypeDefinitionNode && def.name.value == rootName)
          for (final f in def.fields) f.name.value: f
        else if (def is ObjectTypeExtensionNode && def.name.value == rootName)
          for (final f in def.fields) f.name.value: f,
    };
    for (final selection in op.selectionSet.selections) {
      if (selection is! FieldNode || selection.name.value == '__typename') {
        continue;
      }
      final field = rootFields[selection.name.value];
      if (field == null) {
        problems.add(
          '$name: schema has no $rootName.${selection.name.value} field',
        );
        continue;
      }
      final known = field.args.map((a) => a.name.value).toSet();
      for (final arg in selection.arguments) {
        if (!known.contains(arg.name.value)) {
          problems.add(
            '$name: schema field ${selection.name.value} has no '
            '${arg.name.value} argument',
          );
        }
      }
    }
  }
  return problems;
}
