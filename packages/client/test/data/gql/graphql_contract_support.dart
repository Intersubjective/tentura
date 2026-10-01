// Lightweight GraphQL document / SDL helpers for contract tests against the
// fetched `schema.graphql` (no code generation involved).

class GqlField {
  GqlField(this.name, this.sub);

  final String name;
  final List<GqlField>? sub;
}

String stripGqlComments(String s) =>
    s.split('\n').map((l) => l.replaceFirst(RegExp(r'#.*$'), '')).join('\n');

/// Parses the `{ ... }` selection whose opening brace is at [open].
List<GqlField> parseSelectionAt(String s, int open) =>
    _parseSet(s, _Cursor(open)).$1;

class _Cursor {
  _Cursor(this.i);
  int i;
}

(List<GqlField>, int) _parseSet(String s, _Cursor c) {
  assert(s[c.i] == '{');
  c.i++;
  final out = <GqlField>[];
  void ws() {
    while (c.i < s.length && ' \t\r\n,'.contains(s[c.i])) {
      c.i++;
    }
  }

  String name() {
    final m = RegExp(r'\w+').matchAsPrefix(s, c.i)!;
    c.i = m.end;
    return m.group(0)!;
  }

  void skipBalanced(String open, String close) {
    var depth = 0;
    do {
      if (s[c.i] == open) depth++;
      if (s[c.i] == close) depth--;
      c.i++;
    } while (depth > 0);
  }

  while (true) {
    ws();
    if (s[c.i] == '}') {
      c.i++;
      return (out, c.i);
    }
    if (s.startsWith('...', c.i)) {
      c.i += 3;
      ws();
      name();
      ws();
      continue;
    }
    var n = name();
    ws();
    if (s[c.i] == ':') {
      c.i++;
      ws();
      n = name(); // alias: realName
      ws();
    }
    if (s[c.i] == '(') {
      skipBalanced('(', ')');
      ws();
    }
    List<GqlField>? sub;
    if (s[c.i] == '{') {
      sub = _parseSet(s, c).$1;
    }
    out.add(GqlField(n, sub));
  }
}

class GqlOperation {
  GqlOperation({
    required this.kind,
    required this.name,
    required this.variables,
    required this.rootField,
    required this.args,
    required this.selection,
  });

  /// `query` or `mutation`.
  final String kind;
  final String name;

  /// `$name` -> declared type.
  final Map<String, String> variables;
  final String rootField;

  /// argument name -> variable name it is bound to.
  final Map<String, String> args;
  final List<GqlField>? selection;

  static GqlOperation parse(String source) {
    final s = stripGqlComments(source);
    final head = RegExp(
      r'(query|mutation)\s+(\w+)\s*(?:\(([^)]*)\))?\s*\{',
    ).firstMatch(s)!;
    final vars = <String, String>{};
    for (final v in RegExp(
      r'\$(\w+)\s*:\s*([^,$]+)',
    ).allMatches(head.group(3) ?? '')) {
      vars[v.group(1)!] = v.group(2)!.trim();
    }
    var i = head.end;
    final root = RegExp(r'\s*(\w+)').matchAsPrefix(s, i)!;
    i = root.end;
    final args = <String, String>{};
    final rest = s.substring(i).trimLeft();
    i = s.length - rest.length;
    if (s[i] == '(') {
      final close = s.indexOf(')', i);
      for (final a in RegExp(
        r'(\w+)\s*:\s*\$(\w+)',
      ).allMatches(s.substring(i, close))) {
        args[a.group(1)!] = a.group(2)!;
      }
      i = close + 1;
    }
    final after = s.substring(i).trimLeft();
    i = s.length - after.length;
    final sel = s[i] == '{' ? parseSelectionAt(s, i) : null;
    return GqlOperation(
      kind: head.group(1)!,
      name: head.group(2)!,
      variables: vars,
      rootField: root.group(1)!,
      args: args,
      selection: sel,
    );
  }
}

class GqlSchema {
  GqlSchema(this.sdl);

  final String sdl;

  static const scalars = {'String', 'Int', 'Boolean', 'Float', 'ID'};

  String? _block(String keyword, String name) {
    final start = sdl.indexOf('$keyword $name {');
    if (start < 0) return null;
    return sdl.substring(start, sdl.indexOf('\n}', start));
  }

  bool isEnum(String name) => _block('enum', name) != null;

  /// Built-in or schema-declared (`scalar uuid`) leaf type.
  bool isLeaf(String name) =>
      scalars.contains(name) ||
      isEnum(name) ||
      RegExp('^scalar $name\\s*\$', multiLine: true).hasMatch(sdl);

  /// field name -> (raw argument string or null, return type).
  Map<String, (String?, String)>? fields(String type) {
    final b = _block('type', type);
    if (b == null) return null;
    final out = <String, (String?, String)>{};
    String? openField;
    for (final l in b.split('\n').skip(1)) {
      // Hasura fields with many arguments span several lines:
      // `  name(` ... `  ): Type`.
      if (openField != null) {
        final end = RegExp(r'^  \): (.+)$').firstMatch(l);
        if (end != null) {
          out[openField] = (null, end.group(1)!);
          openField = null;
        }
        continue;
      }
      final open = RegExp(r'^  (\w+)\($').firstMatch(l);
      if (open != null) {
        openField = open.group(1);
        continue;
      }
      final m = RegExp(r'^\s+(\w+)(?:\((.*)\))?: (.+)$').firstMatch(l);
      if (m != null) out[m.group(1)!] = (m.group(2), m.group(3)!);
    }
    return out;
  }

  static String baseType(String t) => t.replaceAll(RegExp(r'[\[\]!]'), '');

  /// Problems found when selecting [fields] on [type]; empty when valid.
  List<String> validateSelection(String type, List<GqlField> fields_) {
    final problems = <String>[];
    final available = fields(type);
    if (available == null) return ['type $type is missing from the schema'];
    for (final f in fields_) {
      final def = available[f.name];
      if (def == null) {
        problems.add('$type.${f.name} is not in the schema');
        continue;
      }
      final base = baseType(def.$2);
      final leaf = isLeaf(base);
      if (leaf && f.sub != null) {
        problems.add('$type.${f.name} is a leaf but has a selection');
      } else if (!leaf && f.sub == null) {
        problems.add('$type.${f.name} ($base) needs a selection');
      } else if (!leaf) {
        problems.addAll(validateSelection(base, f.sub!));
      }
    }
    return problems;
  }

  /// Problems with [op] against its root type; empty when valid.
  List<String> validateOperation(GqlOperation op) {
    final root = op.kind == 'query' ? 'query_root' : 'mutation_root';
    final def = fields(root)?[op.rootField];
    if (def == null) return ['$root.${op.rootField} is not in the schema'];
    final problems = <String>[];
    final schemaArgs = <String, String>{};
    for (final a in (def.$1 ?? '').split(RegExp(r',\s+(?=\w+:)'))) {
      final m = RegExp(r'^(\w+): (.+)$').firstMatch(a.trim());
      if (m != null) schemaArgs[m.group(1)!] = m.group(2)!;
    }
    for (final e in op.args.entries) {
      final declared = op.variables[e.value];
      final want = schemaArgs[e.key];
      if (want == null) {
        problems.add('${op.rootField} has no argument ${e.key}');
      } else if (declared == null) {
        problems.add('variable \$${e.value} is not declared');
      } else if (want.split(' = ').first != declared) {
        problems.add(
          '${op.rootField}(${e.key}) is $want but the document declares '
          '$declared',
        );
      }
    }
    for (final a in schemaArgs.entries) {
      final required = a.value.endsWith('!') && !a.value.contains(' = ');
      if (required && !op.args.containsKey(a.key)) {
        problems.add('required argument ${a.key} is not supplied');
      }
    }
    final base = baseType(def.$2);
    final leaf = isLeaf(base);
    if (leaf != (op.selection == null)) {
      problems.add('selection on ${op.rootField} does not match its type');
    } else if (!leaf) {
      problems.addAll(validateSelection(base, op.selection!));
    }
    return problems;
  }
}
