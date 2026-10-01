// tentura-7et: client [BeaconLifecycleChangeReason] must define deleted,
// needsMoreHelp, enoughHelp, and neutralOpen with the same wire strings as
// server. reviewExpired vs closureExpired is out of scope for this bead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_activity_event_consts.dart';

void main() {
  group('BeaconLifecycleChangeReason mirrors server consts (tentura-7et)', () {
    test('server source still defines the coordination lifecycle wire strings', () {
      final server = _parseLifecycleChangeReasons(_readServerConstsSource());
      for (final entry in _coordinationLifecycleReasonWireStrings.entries) {
        expect(
          server[entry.key],
          entry.value,
          reason:
              'server BeaconLifecycleChangeReason.${entry.key} must stay '
              '${entry.value}',
        );
      }
    });

    test(
      'client BeaconLifecycleChangeReason exposes coordination lifecycle reasons',
      () {
        expect(
          BeaconLifecycleChangeReason.deleted,
          _coordinationLifecycleReasonWireStrings['deleted'],
        );
        expect(
          BeaconLifecycleChangeReason.needsMoreHelp,
          _coordinationLifecycleReasonWireStrings['needsMoreHelp'],
        );
        expect(
          BeaconLifecycleChangeReason.enoughHelp,
          _coordinationLifecycleReasonWireStrings['enoughHelp'],
        );
        expect(
          BeaconLifecycleChangeReason.neutralOpen,
          _coordinationLifecycleReasonWireStrings['neutralOpen'],
        );
      },
    );

    test('client source static consts match the compiled API values', () {
      final fromSource = _parseLifecycleChangeReasons(_readClientConstsSource());
      expect(fromSource['deleted'], BeaconLifecycleChangeReason.deleted);
      expect(
        fromSource['needsMoreHelp'],
        BeaconLifecycleChangeReason.needsMoreHelp,
      );
      expect(fromSource['enoughHelp'], BeaconLifecycleChangeReason.enoughHelp);
      expect(fromSource['neutralOpen'], BeaconLifecycleChangeReason.neutralOpen);
    });
  });
}

/// Acceptance-criterion wire strings; fixed so a server rename does not shrink
/// what the client must implement.
const _coordinationLifecycleReasonWireStrings = <String, String>{
  'deleted': 'deleted',
  'needsMoreHelp': 'needsMoreHelp',
  'enoughHelp': 'enoughHelp',
  'neutralOpen': 'neutralOpen',
};

String _readClientConstsSource() => _readFirstExisting(const [
      'lib/domain/entity/beacon_activity_event_consts.dart',
      'packages/client/lib/domain/entity/beacon_activity_event_consts.dart',
    ]);

String _readServerConstsSource() => _readFirstExisting(const [
      '../server/lib/consts/beacon_activity_event_consts.dart',
      'packages/server/lib/consts/beacon_activity_event_consts.dart',
    ]);

String _readFirstExisting(List<String> candidates) {
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError(
    'beacon_activity_event_consts.dart not found; tried: ${candidates.join(', ')}',
  );
}

Map<String, String> _parseLifecycleChangeReasons(String source) {
  final classPattern = RegExp(
    r'abstract final class BeaconLifecycleChangeReason\s*\{([^}]*)\}',
    multiLine: true,
  );
  final match = classPattern.firstMatch(source);
  if (match == null) {
    throw StateError('BeaconLifecycleChangeReason class missing in source');
  }
  final body = match.group(1)!;
  final constPattern = RegExp(r"static const (\w+) = '([^']+)';");
  return {
    for (final m in constPattern.allMatches(body)) m.group(1)!: m.group(2)!,
  };
}
