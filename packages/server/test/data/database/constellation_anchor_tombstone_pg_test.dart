@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '../../support/constellation_anchor_tombstone_fixture.dart';
import '../../support/disposable_pg_target.dart';

typedef _Pins = ConstellationAnchorTombstoneFixture;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_TOMBSTONE_TEST_DB',
    defaultNamePrefix: 'tentura_test_anchor_tombstone',
  );
  final pgSkip = await pgSkipReason(target);

  group(
    'pins retain deleted targets as tombstones',
    () {
      late _Pins fixture;

      setUpAll(() async {
        fixture = _Pins(target);
        await fixture.open();
      });
      tearDownAll(() async => fixture.close());
      setUp(() async => fixture.reset());

      for (final entry in _Pins.targets.entries) {
        final label = entry.key;
        final pinTarget = entry.value;

        test(
          'hard deleting a pinned $label preserves placement and emits one committed hint',
          () async {
            await fixture.pin(pinTarget);
            final before = (await fixture.rows()).single;
            final beforeRevision = await fixture.revision();
            await fixture.clearHints();

            await fixture.writer.runTx((transaction) async {
              await fixture.deleteTarget(pinTarget, transaction: transaction);
              final remaining = await fixture.rows(transaction: transaction);
              expect(
                remaining,
                hasLength(1),
                reason:
                    'Deleting the target must retain the explicitly placed pin',
              );
              _expectSamePlacement(remaining.single, before, pinTarget);
              expect(
                await fixture.revision(transaction: transaction),
                beforeRevision + BigInt.one,
              );
              expect(fixture.hints(), isEmpty);
            });

            await fixture.drainHints();
            _expectSamePlacement(
              (await fixture.rows()).single,
              before,
              pinTarget,
            );
            final committedRevision = await fixture.revision();
            expect(committedRevision, beforeRevision + BigInt.one);
            _expectHint(fixture.hints(), _Pins.viewer, committedRevision);
          },
        );

        for (final projection in ConstellationProjection.values) {
          test(
            '${projection.wireValue} reads return a deleted $label as an identity-only tombstone',
            () async {
              final pin = await fixture.pin(pinTarget);
              await fixture.deleteTarget(pinTarget);
              final storedBeforeRead = await fixture.rows();
              final revisionBeforeRead = await fixture.revision();

              final read = await fixture.read(projection);
              expect(
                read.anchors,
                hasLength(1),
                reason:
                    'The deleted target must remain represented in snapshots',
              );
              final tombstone = read.anchors.single;
              expect(tombstone.target, pinTarget);
              expect(tombstone.position, pin.position);
              expect(tombstone.placedAt, pin.placedAt);
              expect(read.revision.value, revisionBeforeRead);
              _expectIdentityOnlyTombstone(read, pinTarget);
              expect(await fixture.rows(), storedBeforeRead);
              expect(await fixture.revision(), revisionBeforeRead);
            },
          );
        }

        test(
          'unpin removes a deleted $label only for the acting viewer',
          () async {
            await fixture.pin(pinTarget);
            await fixture.pin(pinTarget, viewerId: _Pins.otherViewer);
            await fixture.deleteTarget(pinTarget);
            expect(await fixture.rows(), hasLength(1));
            final otherTombstones = await fixture.rows(
              viewerId: _Pins.otherViewer,
            );
            expect(otherTombstones, hasLength(1));
            final beforeRevision = await fixture.revision();
            await fixture.clearHints();

            final result = await fixture.repository.applyBatch(
              viewerId: _Pins.viewer,
              ops: [
                AnchorApplyOp(
                  clientOpId: 'CAOPtombunpin${pinTarget.kind.wireValue}',
                  kind: AnchorOpKind.delete,
                  target: pinTarget,
                ),
              ],
            );
            expect(result.results.single.status, AnchorOpStatus.ok);
            expect(await fixture.rows(), isEmpty);
            expect(result.afterRevision.value, beforeRevision + BigInt.one);
            expect(
              await fixture.rows(viewerId: _Pins.otherViewer),
              otherTombstones,
            );
            expect(
              (await fixture.read(ConstellationProjection.anchors)).anchors,
              isEmpty,
            );
            await fixture.drainHints();
            _expectHint(
              fixture.hints(),
              _Pins.viewer,
              result.afterRevision.value,
            );
            expect(fixture.hints(_Pins.otherViewer), isEmpty);
          },
        );

        test(
          'applying a placement to a deleted $label rejects the target and preserves its tombstone',
          () async {
            await fixture.pin(pinTarget);
            await fixture.deleteTarget(pinTarget);
            final before = await fixture.rows();
            expect(before, hasLength(1));
            final beforeRevision = await fixture.revision();
            await fixture.clearHints();

            final operation = AnchorApplyOp(
              clientOpId: 'CAOPtombrepin${pinTarget.kind.wireValue}',
              kind: AnchorOpKind.upsert,
              target: pinTarget,
              position: const ConstellationAnchorPosition(
                xUnits: 2,
                yUnits: -1,
                coordinateSpaceVersion: 1,
              ),
            );
            final result = await fixture.repository.applyBatch(
              viewerId: _Pins.viewer,
              ops: [operation],
            );
            expect(result.results.single.status, AnchorOpStatus.rejected);
            expect(result.results.single.reason, 'target_not_found');
            expect(result.results.single.anchor, isNull);
            expect(result.beforeRevision.value, beforeRevision);
            expect(result.afterRevision.value, beforeRevision);
            expect(await fixture.rows(), before);
            expect(await fixture.revision(), beforeRevision);

            final replay = await fixture.repository.applyBatch(
              viewerId: _Pins.viewer,
              ops: [operation],
            );
            expect(replay.results.single.replayed, isTrue);
            expect(replay.results.single.reason, 'target_not_found');
            expect(await fixture.rows(), before);
            await fixture.drainHints();
            expect(fixture.hints(), isEmpty);
          },
        );

        test(
          'rolling back a deleted $label restores the pin without a tombstone hint',
          () async {
            await fixture.pin(pinTarget);
            final before = await fixture.rows();
            final beforeRevision = await fixture.revision();
            await fixture.clearHints();

            await expectLater(
              fixture.writer.runTx((transaction) async {
                await fixture.deleteTarget(pinTarget, transaction: transaction);
                final inTransaction = await fixture.rows(
                  transaction: transaction,
                );
                expect(inTransaction, hasLength(1));
                _expectSamePlacement(
                  inTransaction.single,
                  before.single,
                  pinTarget,
                );
                expect(
                  await fixture.revision(transaction: transaction),
                  beforeRevision + BigInt.one,
                );
                throw const _RollbackTargetDeletion();
              }),
              throwsA(isA<_RollbackTargetDeletion>()),
            );
            expect(await fixture.rows(), before);
            expect(await fixture.revision(), beforeRevision);
            final table = pinTarget.kind == ConstellationAnchorTargetKind.beacon
                ? 'public.beacon'
                : 'public."user"';
            final targetRows = await fixture.writer.execute(
              Sql.named('SELECT id FROM $table WHERE id = @id'),
              parameters: {'id': pinTarget.id},
            );
            expect(targetRows, hasLength(1));
            await fixture.drainHints();
            expect(fixture.hints(), isEmpty);
          },
        );
      }

      test(
        'deleting a shared target tombstones each viewer pin with its own cursor and hint',
        () async {
          final person = _Pins.targets['person']!;
          await fixture.pin(person);
          await fixture.pin(person, viewerId: _Pins.otherViewer);
          final viewerBefore = await fixture.revision();
          final otherBefore = await fixture.revision(
            viewerId: _Pins.otherViewer,
          );
          await fixture.clearHints();

          await fixture.deleteTarget(person);
          expect(await fixture.rows(), hasLength(1));
          expect(await fixture.rows(viewerId: _Pins.otherViewer), hasLength(1));
          expect(await fixture.revision(), viewerBefore + BigInt.one);
          expect(
            await fixture.revision(viewerId: _Pins.otherViewer),
            otherBefore + BigInt.one,
          );
          await fixture.drainHints();
          _expectHint(fixture.hints(), _Pins.viewer, viewerBefore + BigInt.one);
          _expectHint(
            fixture.hints(_Pins.otherViewer),
            _Pins.otherViewer,
            otherBefore + BigInt.one,
          );
        },
      );

      test(
        'deleting an author account tombstones the person pin and preserves the surviving Request pin',
        () async {
          await fixture.reset(beaconAuthorId: _Pins.person);
          for (final target in _Pins.targets.values) {
            await fixture.pin(target);
          }
          final before = await fixture.rows();
          final beforeRevision = await fixture.revision();
          await fixture.clearHints();
          // beacon_owner_or_deleted_ck: an authorless Request must be deleted
          // (status 2); a live one is retained only if it keeps its author.
          // Mark it deleted so the author FK can clear without a cascade.
          await fixture.writer.execute(
            Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
            parameters: {'id': _Pins.beacon},
          );
          await fixture.clearHints();

          await fixture.deleteTarget(_Pins.targets['person']!);
          final after = await fixture.rows();
          expect(after, hasLength(2));
          final personBefore = before.singleWhere(
            (row) => row['person_id'] == _Pins.person,
          );
          _expectSamePlacement(
            after.singleWhere((row) => row['id'] == personBefore['id']),
            personBefore,
            _Pins.targets['person']!,
          );
          final requestBefore = before.singleWhere(
            (row) => row['beacon_id'] == _Pins.beacon,
          );
          final requestAfter = after.singleWhere(
            (row) => row['id'] == requestBefore['id'],
          );
          expect(requestAfter, requestBefore);
          expect(requestAfter, containsPair('beacon_id', _Pins.beacon));
          expect(requestAfter, containsPair('tombstone_at', null));
          // Author deletion clears beacon.user_id; it does not delete the Request.
          final survivingRequest = await fixture.writer.execute(
            Sql.named('SELECT user_id FROM public.beacon WHERE id = @id'),
            parameters: {'id': _Pins.beacon},
          );
          expect(survivingRequest, hasLength(1));
          expect(survivingRequest.single.single, isNull);
          expect(await fixture.revision(), beforeRevision + BigInt.one);
          await fixture.drainHints();
          _expectHint(
            fixture.hints(),
            _Pins.viewer,
            beforeRevision + BigInt.one,
          );
        },
      );

      test(
        'deleting the viewer account removes its tombstones and cursor without recreation',
        () async {
          // The viewer must not author the open Request (beacon_owner_or_deleted_ck).
          await fixture.reset(beaconAuthorId: _Pins.otherViewer);
          await fixture.pin(_Pins.targets['person']!);
          await fixture.deleteTarget(_Pins.targets['person']!);
          expect(await fixture.rows(), hasLength(1));
          await fixture.clearHints();

          await fixture.writer.execute(
            Sql.named('DELETE FROM public."user" WHERE id = @viewer'),
            parameters: {'viewer': _Pins.viewer},
          );
          expect(await fixture.rows(), isEmpty);
          final cursor = await fixture.writer.execute(
            Sql.named('''
SELECT viewer_id FROM public.constellation_anchor_cursor WHERE viewer_id = @viewer
'''),
            parameters: {'viewer': _Pins.viewer},
          );
          expect(cursor, isEmpty);
          await fixture.drainHints();
          expect(fixture.hints(), isEmpty);
        },
      );
    },
    skip: pgSkip,
  );
}

void _expectSamePlacement(
  Map<String, dynamic> tombstone,
  Map<String, dynamic> original,
  ConstellationAnchorTarget target,
) {
  expectRetainedPinTombstone(tombstone, original, target);
}

void _expectHint(
  List<Map<String, dynamic>> hints,
  String viewer,
  BigInt revision,
) {
  expect(hints, hasLength(1));
  expect(hints.single['event'], 'update');
  expect(hints.single['id'], viewer);
  expect(hints.single['user_ids'], [viewer]);
  expect(hints.single['revision'], revision.toString());
}

void _expectIdentityOnlyTombstone(
  ConstellationAnchorProjection projection,
  ConstellationAnchorTarget target,
) {
  final wire = constellationAnchorProjectionToGqlMap(projection);
  final placements = wire['anchors'] as List;
  final placement = placements.single as Map<String, dynamic>;
  expect(placement['targetId'], target.id);
  expect(placement['targetKind'], target.kind.wireValue);

  final targetKey = target.kind == ConstellationAnchorTargetKind.beacon
      ? 'pinnedRequests'
      : 'pinnedPeers';
  final targetRecords = wire[targetKey] as List;
  expect(
    targetRecords,
    hasLength(1),
    reason: 'The matching target collection must contain its placeholder',
  );
  final targetRecord = targetRecords.single as Map<String, dynamic>;
  expect(targetRecord['id'], target.id);
  expect(
    targetRecord['pinState'],
    'tombstone',
    reason: 'The matching target record must carry the tombstone state',
  );
  expect(placement['pinState'], anyOf(isNull, 'tombstone'));
  _expectNoContent(
    placement,
    const {
      'id',
      'targetId',
      'targetKind',
      'xUnits',
      'yUnits',
      'coordinateSpaceVersion',
      'revision',
      'placedAt',
      'pinState',
    },
  );
  _expectNoContent(targetRecord, const {
    'id',
    'kind',
    'targetKind',
    'pinState',
  });
  expect(projection.supportPeers, isEmpty);
  expect(projection.supportEdges, isEmpty);
}

void _expectNoContent(
  Map<String, dynamic> record,
  Set<String> identityAndPlacementFields,
) {
  for (final entry in record.entries) {
    if (!identityAndPlacementFields.contains(entry.key)) {
      expect(
        entry.value,
        isNull,
        reason: 'A tombstone must not expose ${entry.key}',
      );
    }
  }
}

final class _RollbackTargetDeletion implements Exception {
  const _RollbackTargetDeletion();
}
