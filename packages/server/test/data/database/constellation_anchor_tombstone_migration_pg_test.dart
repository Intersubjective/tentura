@Tags(['pg', 'mr'])
library;

import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';

import '../../support/constellation_anchor_tombstone_fixture.dart';
import '../../support/disposable_pg_target.dart';

const _previousVersion = '0235';
const _tombstoneVersion = '0236';
typedef _Pins = ConstellationAnchorTombstoneFixture;

Future<void> main() async {
  test(
    'registers an additive deleted-pin tombstone migration after the existing schema',
    () {
      final versions = migrationsForTesting
          .map((migration) => migration.version)
          .toList();
      expect(
        versions.where((version) => version == _tombstoneVersion),
        hasLength(1),
        reason:
            'Tombstones require a new registered migration, not a baseline edit',
      );
      expect(
        versions.indexOf(_tombstoneVersion),
        versions.indexOf(_previousVersion) + 1,
      );
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_TOMBSTONE_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_anchor_tomb_mig',
  );
  final pgSkip = await pgSkipReason(target);

  group(
    'deleted-pin tombstone schema upgrade',
    () {
      late _Pins fixture;

      setUpAll(() async {
        fixture = _Pins(target);
        await fixture.open(throughVersion: _previousVersion);
        await fixture.reset();
        await fixture.pin(_Pins.targets['Request']!);
        await fixture.pin(_Pins.targets['person']!);
      });
      tearDownAll(() async => fixture.close());

      test(
        'upgrading existing pins and replaying the migration preserve live pins and tombstones',
        () async {
          final initialVersion = await fixture.writer.execute(
            'SELECT max(version) FROM public.schema_version',
          );
          expect(initialVersion.single.single, _previousVersion);
          final additions = migrationsForTesting.where(
            (migration) => migration.version == _tombstoneVersion,
          );
          expect(
            additions,
            hasLength(1),
            reason: 'The tombstone migration must be registered',
          );
          final migration = additions.single;
          final liveBefore = await fixture.rows();
          await fixture.clearHints();

          await migrateDbSchemaThrough(fixture.writer, migration.version);
          final liveAfterUpgrade = await fixture.rows();
          expect(liveAfterUpgrade, hasLength(2));
          for (final old in liveBefore) {
            final upgraded = liveAfterUpgrade.singleWhere(
              (row) => row['id'] == old['id'],
            );
            for (final field in old.keys.where(
              (field) => field != 'revision',
            )) {
              expect(
                upgraded[field],
                old[field],
                reason: 'Upgrade preserves existing $field',
              );
            }
          }
          final revisionAfterUpgrade = await fixture.revision();
          await fixture.clearHints();

          // Replay statements, not just migrant's already-recorded-version path.
          await fixture.writer.runTx((transaction) async {
            for (final statement in migration.statements) {
              await transaction.execute(statement);
            }
          });
          expect(await fixture.rows(), liveAfterUpgrade);
          expect(await fixture.revision(), revisionAfterUpgrade);
          await fixture.drainHints();
          expect(fixture.hints(), isEmpty);

          for (final target in _Pins.targets.values) {
            await fixture.deleteTarget(target);
          }
          final tombstones = await fixture.rows();
          expect(tombstones, hasLength(2));
          for (final target in _Pins.targets.values) {
            final liveTargetColumn = switch (target.kind) {
              ConstellationAnchorTargetKind.beacon => 'beacon_id',
              ConstellationAnchorTargetKind.person => 'person_id',
            };
            final original = liveAfterUpgrade.singleWhere(
              (row) => row[liveTargetColumn] == target.id,
            );
            expectRetainedPinTombstone(
              tombstones.singleWhere((row) => row['id'] == original['id']),
              original,
              target,
            );
          }
          expect(
            (await fixture.read(
              ConstellationProjection.anchors,
            )).anchors.map((anchor) => anchor.target).toSet(),
            _Pins.targets.values.toSet(),
          );
          final tombstoneRevision = await fixture.revision();
          expect(tombstoneRevision, revisionAfterUpgrade + BigInt.two);
          await fixture.clearHints();

          await fixture.writer.runTx((transaction) async {
            for (final statement in migration.statements) {
              await transaction.execute(statement);
            }
          });
          await migrateDbSchemaThrough(fixture.writer, migration.version);
          expect(await fixture.rows(), tombstones);
          expect(await fixture.revision(), tombstoneRevision);
          await fixture.drainHints();
          expect(fixture.hints(), isEmpty);
          final versions = await fixture.writer.execute(
            "SELECT version FROM public.schema_version WHERE version = '$_tombstoneVersion'",
          );
          expect(versions, hasLength(1));
        },
      );
    },
    skip: pgSkip,
  );
}
