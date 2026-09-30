/// Shared with tentura-0exd: detect real SQL usage of trust objects dropped in m0202.
library;

const m0202DroppedTrustFunctions = [
  'trust_apply_source_evidence',
  'trust_rebuild_effective_edge',
];

const m0202DroppedTrustTables = [
  'user_trust_source_edge',
  'trust_evidence_event',
];

const m0202DroppedTrustObjects = [
  ...m0202DroppedTrustFunctions,
  ...m0202DroppedTrustTables,
];

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

String stripDartAndSqlComments(String s) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  var raw = false;

  int blankLine(int from) {
    var j = from;
    while (j < s.length && s[j] != '\n') {
      if (quote != null && s.startsWith(quote, j)) break;
      out.write(' ');
      j++;
    }
    return j;
  }

  while (i < s.length) {
    final c = s[i];
    if (quote == null) {
      if (s.startsWith('//', i)) {
        i = blankLine(i);
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        final stop = end == -1 ? s.length : end + 2;
        for (; i < stop; i++) {
          out.write(s[i] == '\n' ? '\n' : ' ');
        }
      } else if (c == "'" || c == '"') {
        raw =
            i > 0 &&
            s[i - 1] == 'r' &&
            (i < 2 || !RegExp(r'\w').hasMatch(s[i - 2]));
        quote = s.startsWith(c * 3, i) ? c * 3 : c;
        out.write(quote);
        i += quote.length;
      } else {
        out.write(c);
        i++;
      }
      continue;
    }
    if (!raw && c == r'\' && i + 1 < s.length) {
      out.write(s.substring(i, i + 2));
      i += 2;
    } else if (s.startsWith(quote, i)) {
      out.write(quote);
      i += quote.length;
      quote = null;
    } else if (quote!.length == 1 && c == '\n') {
      out.write(c);
      i++;
      quote = null;
    } else if (s.startsWith('--', i) &&
        (i == 0 ||
            _isSpace(s[i - 1]) ||
            s.startsWith(quote, i - quote!.length)) &&
        (i + 2 >= s.length ||
            _isSpace(s[i + 2]) ||
            s.startsWith(quote, i + 2))) {
      i = blankLine(i);
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

List<int> sqlUsageLineNumbers(String source, String object) {
  final code = stripDartAndSqlComments(source);
  final patterns = [
    RegExp('\\b$object\\s*\\('),
    RegExp(
      '\\b(FROM|INTO|JOIN|UPDATE|TABLE|TRUNCATE)\\s+(public\\.)?$object\\b',
      caseSensitive: false,
    ),
    RegExp(
      "\\bto_reg(class|proc|procedure|type)\\s*\\(\\s*'(public\\.)?$object\\b",
      caseSensitive: false,
    ),
    RegExp(
      '\\b(proname|relname|tablename|table_name|routine_name)\\s*'
      "(=|IN\\s*\\()\\s*(?:'[^']*'\\s*,\\s*)*'(public\\.)?$object'",
      caseSensitive: false,
    ),
  ];
  final lines = <int>{};
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(code)) {
      lines.add('\n'.allMatches(code.substring(0, match.start)).length + 1);
    }
  }
  return lines.toList()..sort();
}

Map<String, List<int>> droppedTrustSqlUsageInSource(String source) {
  final offenders = <String, List<int>>{};
  for (final object in m0202DroppedTrustObjects) {
    final lines = sqlUsageLineNumbers(source, object);
    if (lines.isNotEmpty) {
      offenders[object] = lines;
    }
  }
  return offenders;
}

Set<String> deletePublicTableTargets(String source) {
  final code = stripDartAndSqlComments(source);
  final matches = RegExp(
    r'DELETE\s+FROM\s+public\.("user"|\w+)',
    caseSensitive: false,
  ).allMatches(code);
  return {
    for (final m in matches)
      m.group(1)!.replaceAll('"', ''),
  };
}

String extractDartFunctionBody(String source, String functionName) {
  final signature = RegExp(
    'Future<void>\\s+$functionName\\s*\\(',
  ).firstMatch(source);
  if (signature == null) {
    throw StateError('function $functionName not found');
  }
  final braceStart = source.indexOf('{', signature.end);
  if (braceStart == -1) {
    throw StateError('function $functionName has no body');
  }
  var depth = 0;
  for (var i = braceStart; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(braceStart + 1, i);
      }
    }
  }
  throw StateError('unterminated body for $functionName');
}
