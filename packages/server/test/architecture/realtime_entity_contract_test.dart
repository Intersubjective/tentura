import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('realtime manifest maps every kind to a live server publisher', () {
    final contractFile = _contractFile();
    final contract = jsonDecode(contractFile.readAsStringSync()) as Map;
    final entries = (contract['kinds']! as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    final repoRoot = contractFile.parent.parent.parent;
    // Squashed baseline (m0193.dart) plus post-baseline parts from
    // _migrations.dart (m0194.dart, m0195.dart, m0196.dart, m0197.dart,
    // m0198.dart, m0199.dart, m0200.dart, m0201.dart, m0202.dart, m0203.dart, …).
    final publisherMigrations = _readPublisherMigrationBodies(repoRoot);

    final triggerArgs = <String>{};
    final specializedPublishers = <String>{};
    for (final entry in entries) {
      final wireKind = entry['wireKind']! as String;
      final entryTriggerArgs = (entry['genericTriggerArgs']! as List)
          .cast<String>();
      final entryPublishers = (entry['specializedPublishers']! as List)
          .cast<String>();
      expect(
        entryTriggerArgs.isNotEmpty || entryPublishers.isNotEmpty,
        isTrue,
        reason: '$wireKind has no server producer',
      );
      for (final triggerArg in entryTriggerArgs) {
        expect(triggerArgs.add(triggerArg), isTrue, reason: triggerArg);
        expect(
          publisherMigrations,
          contains("'$triggerArg'"),
          reason: '$wireKind trigger argument is absent from migrations',
        );
      }
      for (final publisher in entryPublishers) {
        expect(
          specializedPublishers.add(publisher),
          isTrue,
          reason: publisher,
        );
        expect(
          publisherMigrations,
          contains('FUNCTION public.$publisher'),
          reason: '$wireKind publisher is absent from migrations',
        );
      }
    }

    expect(triggerArgs, isNotEmpty);
    expect(specializedPublishers, isNotEmpty);
    expect(
      specializedPublishers,
      {
        'notify_coordination_change',
        'notify_help_offer_admission_event_change',
        'notify_beacon_hierarchy_admission_change',
        'notify_beacon_plan_change',
        'notify_beacon_hierarchy_beacon_change',
        'notify_beacon_hierarchy_promotion_change',
        'notify_constellation_anchor_change',
        'notify_invite_seed_prompt_state_change',
        'notify_notification_outbox_delete',
        'notify_notification_outbox_insert',
        'notify_notification_outbox_update',
        'notify_relationship_change',
        'notify_room_message_attachment_change',
        'notify_people_seen_change',
        'notify_room_seen_peer_change',
      },
    );

    final notification = entries.singleWhere(
      (entry) => entry['wireKind'] == 'notification',
    );
    expect(
      (notification['impacts']! as List).cast<String>(),
      containsAll(const ['updates_feed', 'updates_badge']),
    );
  });
}

File _contractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) return file.absolute;
  }
  throw StateError('Realtime entity contract manifest not found');
}

String _readPublisherMigrationBodies(Directory repoRoot) {
  final migrationDir = repoRoot.uri.resolve(
    'packages/server/lib/data/database/migration/',
  );
  final buffer = StringBuffer();
  buffer.write(
    File.fromUri(migrationDir.resolve('m0193.dart')).readAsStringSync(),
  );
  final registry = File.fromUri(
    migrationDir.resolve('_migrations.dart'),
  ).readAsStringSync();
  for (final match in RegExp(r"part '(m\d+\.dart)'").allMatches(registry)) {
    final name = match.group(1)!;
    final version = int.parse(name.substring(1, 5));
    if (version > 193) {
      buffer.write(File.fromUri(migrationDir.resolve(name)).readAsStringSync());
    }
  }
  return buffer.toString();
}
