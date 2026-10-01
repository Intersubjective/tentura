// tentura-7xz: detect raw interpolated GraphQL passed to _postGraphQl in sources.

/// GraphQL operation keyword at document start (after optional whitespace).
final _graphqlDocumentLead = RegExp(
  r'^\s*(query|mutation|subscription)\s*(\w+\s*)?[({]',
  multiLine: true,
);

final _dartInterpolation = RegExp(r'\$(?:\{|[A-Za-z_])');

/// Every `_postGraphQl(` call site whose first argument is a string expression
/// embedding a GraphQL document with Dart interpolation (tentura-7xz defect).
List<int> findPostGraphQlRawInterpolatedGraphqlCallOffsets(String source) {
  final callPattern = RegExp(r'_postGraphQl\s*\(');
  final offsets = <int>[];
  for (final match in callPattern.allMatches(source)) {
    final openParen = match.end - 1;
    final argExpression = _firstArgumentExpression(source, openParen);
    if (argExpression == null) {
      continue;
    }
    if (_isRawInterpolatedGraphqlStringExpression(argExpression)) {
      offsets.add(match.start);
    }
  }
  return offsets;
}

int countPostGraphQlRawInterpolatedGraphqlCallSites(String source) {
  return findPostGraphQlRawInterpolatedGraphqlCallOffsets(source).length;
}

bool _isRawInterpolatedGraphqlStringExpression(String argumentExpression) {
  if (!_dartInterpolation.hasMatch(argumentExpression)) {
    return false;
  }
  final literalBodies = _stringLiteralBodies(argumentExpression);
  if (literalBodies.isEmpty) {
    return false;
  }
  final combined = literalBodies.join();
  return _graphqlDocumentLead.hasMatch(combined);
}

String? _firstArgumentExpression(String source, int openParenIndex) {
  var i = openParenIndex + 1;
  final start = i;
  i = _skipWsAndLineComments(source, i);
  if (i >= source.length) {
    return null;
  }
  final first = source[i];
  if (first != "'" && first != '"') {
    return null;
  }
  final argStart = i;
  i = _scanAdjacentStringLiterals(source, i);
  return source.substring(argStart, i);
}

int _skipWsAndLineComments(String source, int i) {
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
      i++;
      continue;
    }
    if (c == 0x2f &&
        i + 1 < source.length &&
        source.codeUnitAt(i + 1) == 0x2f) {
      final newline = source.indexOf('\n', i);
      if (newline < 0) {
        return source.length;
      }
      i = newline + 1;
      continue;
    }
    break;
  }
  return i;
}

int _scanAdjacentStringLiterals(String source, int i) {
  while (i < source.length) {
    final c = source[i];
    if (c != "'" && c != '"') {
      break;
    }
    i = _scanDartStringLiteral(source, i);
    i = _skipWsAndLineComments(source, i);
  }
  return i;
}

int _scanDartStringLiteral(String source, int start) {
  final quote = source[start];
  var i = start + 1;
  while (i < source.length) {
    final c = source[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == r'$') {
      if (i + 1 < source.length && source[i + 1] == '{') {
        i += 2;
        while (i < source.length) {
          if (source[i] == '{') {
            i = _scanBalancedBraces(source, i);
          } else if (source[i] == '}') {
            i++;
            break;
          } else {
            i++;
          }
        }
      } else {
        i++;
        while (i < source.length &&
            _isIdentifierChar(source.codeUnitAt(i))) {
          i++;
        }
      }
      continue;
    }
    if (c == quote) {
      return i + 1;
    }
    i++;
  }
  return source.length;
}

int _scanBalancedBraces(String source, int openIndex) {
  var depth = 0;
  var i = openIndex;
  while (i < source.length) {
    final c = source[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) {
        return i + 1;
      }
    } else if (c == r'\') {
      i++;
    }
    i++;
  }
  return source.length;
}

bool _isIdentifierChar(int codeUnit) {
  return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
      codeUnit == 0x5f;
}

List<String> _stringLiteralBodies(String argumentExpression) {
  final bodies = <String>[];
  var i = 0;
  while (i < argumentExpression.length) {
    i = _skipWsAndLineComments(argumentExpression, i);
    if (i >= argumentExpression.length) {
      break;
    }
    final c = argumentExpression[i];
    if (c != "'" && c != '"') {
      break;
    }
    final quote = c;
    i++;
    final start = i;
    while (i < argumentExpression.length) {
      final ch = argumentExpression[i];
      if (ch == r'\') {
        i += 2;
        continue;
      }
      if (ch == r'$') {
        i++;
        if (i < argumentExpression.length && argumentExpression[i] == '{') {
          i = _scanBalancedBraces(argumentExpression, i);
        } else {
          while (i < argumentExpression.length &&
              _isIdentifierChar(argumentExpression.codeUnitAt(i))) {
            i++;
          }
        }
        continue;
      }
      if (ch == quote) {
        bodies.add(argumentExpression.substring(start, i));
        i++;
        break;
      }
      i++;
    }
    i = _skipWsAndLineComments(argumentExpression, i);
  }
  return bodies;
}
