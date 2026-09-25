// tentura-1ev landing gate acceptance (trial merge steward + tentura-rsm)

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _architectureTestRelative =
    'test/architecture/realtime_entity_contract_test.dart';

const _migrationsRegistryRelative =
    'lib/data/database/migration/_migrations.dart';

const _migrationDirRelative = 'lib/data/database/migration';

File _serverFile(String relativePath) {
  for (final prefix in const ['../../packages/server/', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Server file not found: $relativePath');
}

File _repoContractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Realtime entity contract manifest not found');
}

Set<String> _contractSpecializedPublishers() {
  final contract =
      jsonDecode(_repoContractFile().readAsStringSync()) as Map<String, dynamic>;
  final kinds = (contract['kinds']! as List).cast<Map>();
  final publishers = <String>{};
  for (final entry in kinds) {
    publishers.addAll(
      (entry['specializedPublishers']! as List).cast<String>(),
    );
  }
  return publishers;
}

Set<String> _postBaselineMigrationPartNames() {
  final registry = _serverFile(_migrationsRegistryRelative).readAsStringSync();
  final parts = <String>{};
  for (final match in RegExp(r"part '(m\d+\.dart)'").allMatches(registry)) {
    final name = match.group(1)!;
    final version = int.parse(name.substring(1, 5));
    if (version > 193) {
      parts.add(name);
    }
  }
  return parts;
}

Set<String> _specializedPublishersDeclaredInArchitectureTest() {
  final source = _serverFile(_architectureTestRelative).readAsStringSync();
  final block = RegExp(
    r'specializedPublishers,\s*\{([^}]*)\}',
    multiLine: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: 'architecture test publisher set block');
  final names = <String>{};
  for (final match in RegExp(r"'([^']+)'").allMatches(block!.group(1)!)) {
    names.add(match.group(1)!);
  }
  return names;
}

String _readShippedPublisherMigrationBodies() {
  final buffer = StringBuffer();
  buffer.write(_serverFile('lib/data/database/migration/m0193.dart').readAsStringSync());
  for (final part in _postBaselineMigrationPartNames()) {
    buffer.write(
      _serverFile('$_migrationDirRelative/$part').readAsStringSync(),
    );
  }
  return buffer.toString();
}

void main() {
  group('trial merge landing check (tentura-1ev)', () {
    test(
      'realtime_entity_contract_test scans every post-baseline migration part',
      () {
        final architectureTest =
            _serverFile(_architectureTestRelative).readAsStringSync();
        final postBaseline = _postBaselineMigrationPartNames();
        expect(
          postBaseline,
          isNotEmpty,
          reason: '_migrations.dart must list migrations after m0193',
        );
        for (final part in postBaseline) {
          expect(
            architectureTest,
            contains(part),
            reason:
                'publisher scan must include $_migrationDirRelative/$part',
          );
        }
      },
    );

    test(
      'realtime_entity_contract_test specializedPublishers matches contract manifest',
      () {
        expect(
          _specializedPublishersDeclaredInArchitectureTest(),
          _contractSpecializedPublishers(),
          reason:
              'architecture test hardcoded publisher set must track contract JSON',
        );
      },
    );

    test(
      'notify_room_seen_peer_change ships in appended migrations and is contract-bound',
      () {
        final bodies = _readShippedPublisherMigrationBodies();
        expect(
          bodies,
          contains('FUNCTION public.notify_room_seen_peer_change'),
          reason: 'm0196 must define the room_seen_peer NOTIFY publisher',
        );
        expect(
          _contractSpecializedPublishers(),
          contains('notify_room_seen_peer_change'),
          reason: 'contract manifest must list room_seen_peer publisher',
        );
      },
    );
  });
}
