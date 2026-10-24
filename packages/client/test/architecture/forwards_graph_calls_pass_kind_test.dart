@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #501: the forwards graph names a Post as a post only when the caller says
/// so (`kind:`); a call without it reads "request" until the beacon loads.
/// Every caller in the app knows the beacon it opens the graph for, so every
/// call passes its kind.
const _definition = 'lib/ui/bloc/screen_cubit.dart';

/// The argument lists of every `showForwardsGraphFor(...)` call in [source].
List<String> forwardsGraphCallArgs(String source) {
  final calls = <String>[];
  final start = RegExp(r'\.\s*showForwardsGraphFor\s*\(');
  for (final match in start.allMatches(source)) {
    var depth = 1;
    var i = match.end;
    for (; i < source.length && depth > 0; i++) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
    }
    calls.add(source.substring(match.end, i - 1));
  }
  return calls;
}

void main() {
  test('the call scanner sees a call with and without kind', () {
    final args = forwardsGraphCallArgs(
      'a.showForwardsGraphFor(b.id); '
      'cubit\n  .showForwardsGraphFor(\n  f(b).id,\n  kind: b.kind,\n);',
    );
    expect(args, hasLength(2));
    expect(args.first, isNot(contains('kind:')));
    expect(args.last, contains('kind:'));
  });

  test('every showForwardsGraphFor call passes the beacon kind', () {
    final root = Directory('lib').existsSync()
        ? Directory('lib')
        : Directory('packages/client/lib');
    final prefix = root.path.substring(0, root.path.length - 'lib'.length);
    final offenders = <String>[];
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.substring(prefix.length);
      if (path == _definition) continue;
      for (final args in forwardsGraphCallArgs(entity.readAsStringSync())) {
        if (!args.contains('kind:')) offenders.add('$path: ($args)');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'pass kind: so a Post forwards graph is not titled a request',
    );
  });
}
