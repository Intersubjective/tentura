@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Constellation drag availability has no write-I/O gate', () {
    final packageRoot = Directory('lib/features').existsSync()
        ? ''
        : 'packages/client/';

    // Whether a node can be dragged is decided by kind and ownership; none of
    // these write-in-flight bookkeeping members may remain anywhere in lib.
    for (final removed in [
      'placementActionsEnabled',
      'hasPendingWrite',
      'deferredRefreshTargets',
      '_placementBusy',
      '_outstandingWrites',
      '_placementSeq',
    ]) {
      test('no source under lib references $removed', () {
        final files = Directory('${packageRoot}lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList();
        expect(files, isNotEmpty);

        final violations = <String>[];
        for (final file in files) {
          final lines = file.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            if (lines[index].contains(removed)) {
              violations.add(
                '${file.path}:${index + 1}: ${lines[index].trim()}',
              );
            }
          }
        }

        expect(
          violations,
          isEmpty,
          reason: 'Drag availability must not depend on write I/O state.',
        );
      });
    }

    test('canDragNode decides from node kind and ownership only', () {
      final source = File(
        '${packageRoot}lib/features/constellation/ui/bloc/'
        'constellation_cubit.dart',
      ).readAsStringSync();
      final start = source.indexOf('bool canDragNode(NodeDetails node)');
      expect(start, isNonNegative, reason: 'canDragNode must exist');

      final open = source.indexOf('{', start);
      var depth = 0;
      var end = open;
      for (; end < source.length; end++) {
        if (source[end] == '{') depth++;
        if (source[end] == '}' && --depth == 0) break;
      }
      final body = source.substring(open, end + 1);

      for (final dependency in [
        'state.',
        'placement',
        'Placement',
        'Pending',
        '_interaction',
      ]) {
        expect(
          body.contains(dependency),
          isFalse,
          reason:
              'canDragNode must not read placement/write state '
              '("$dependency" found in:\n$body)',
        );
      }
    });
  });
}
