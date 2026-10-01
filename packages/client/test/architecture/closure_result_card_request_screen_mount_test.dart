import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tentura-q8s8 / A22: `ClosureResultCard` must appear on the request screen
/// (beacon detail / NOW surface under `features/beacon_view/`) for closed
/// requests, not only in its isolated widget test.
void main() {
  const cardPath =
      'lib/features/closure/ui/widget/closure_result_card.dart';
  const requestScreenRoot = 'lib/features/beacon_view';

  final closureResultCardMount = RegExp(r'\bClosureResultCard\s*\(');

  Iterable<File> requestScreenDartFiles() sync* {
    final root = Directory(requestScreenRoot);
    if (!root.existsSync()) return;
    yield* root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) =>
              !f.path.endsWith('.g.dart') &&
              !f.path.endsWith('.gql.dart') &&
              !f.path.endsWith('.freezed.dart') &&
              !f.path.endsWith('.gr.dart'),
        );
  }

  List<String> mountSitesUnderRequestScreen() {
    final sites = <String>[];
    for (final file in requestScreenDartFiles()) {
      if (file.path == cardPath) continue;
      if (closureResultCardMount.hasMatch(file.readAsStringSync())) {
        sites.add(file.path);
      }
    }
    return sites;
  }

  test('request screen mounts ClosureResultCard under features/beacon_view', () {
    final sites = mountSitesUnderRequestScreen();
    expect(
      sites,
      isNotEmpty,
      reason:
          'mount ClosureResultCard on the request screen (within '
          '$requestScreenRoot), not only in $cardPath',
    );
  });

  test('request-screen ClosureResultCard mount is gated on closed status', () {
    final sites = mountSitesUnderRequestScreen();
    expect(sites, isNotEmpty, reason: 'no ClosureResultCard mount to gate');
    for (final path in sites) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('BeaconStatus.closed'),
        isTrue,
        reason:
            '$path mounts ClosureResultCard but does not gate on '
            'BeaconStatus.closed',
      );
    }
  });
}
