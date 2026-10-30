// Snapshot reads reach MeritRank through person_visible_peer_ids_tx (m0222),
// even without trust edges in the fixture. Keep this suite serialized with mr.
@Tags(['pg', 'mr'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/mappers/constellation_gql_maps.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';

import '../../support/constellation_anchor_tombstone_fixture.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

typedef _Pins = ConstellationAnchorTombstoneFixture;

const _someoneElse = _Pins.otherViewer;
const _mutualBlockPeer = 'Ucatombmutual';
const _privateTitle = 'Private Request title';

/// Contract: docs/plans/issue-235-constellation-interactive-architecture.md,
/// binding owner decision D15 and rev 10 section 5.10; implementation plan U54
/// explicitly requires these server read tests.
/// A pin beats visibility but not blocks, and never grants access. A block by
/// the other side hides the target; a block by the viewer keeps it, marked. A
/// pinned Request the read wall denies stays at its pin as a content-free
/// placeholder instead of silently vanishing.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PIN_PLACEHOLDERS_TEST_DB',
    defaultNamePrefix: 'tentura_test_pin_placeholders',
  );
  final pgSkip = await pgSkipReason(target);

  group(
    'pinned targets keep their place according to blocks and read access',
    () {
      late _Pins fixture;

      Future<void> block(String blockerId, String blockedId) =>
          fixture.writer.execute(
            Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocker)
'''),
            parameters: {'blocker': blockerId, 'blocked': blockedId},
          );

      Future<void> unblock(String blockerId, String blockedId) =>
          fixture.writer.execute(
            Sql.named('''
DELETE FROM public.user_block
WHERE blocker_id = @blocker AND blocked_id = @blocked
'''),
            parameters: {'blocker': blockerId, 'blocked': blockedId},
          );

      Future<void> insertRequest(String id, String authorId) =>
          fixture.writer.execute(
            Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, created_at, updated_at, published_at)
VALUES (@id, @author, '$_privateTitle', 'Private Request description', 0,
        '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
            parameters: {'id': id, 'author': authorId},
          );

      /// An active help offer is what lets the viewer read someone else's
      /// Request without any trust path.
      Future<void> offerHelp(String beaconId) => fixture.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer
  (beacon_id, user_id, message, status, created_at, updated_at)
VALUES (@beacon, @viewer, 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
        parameters: {'beacon': beaconId, 'viewer': _Pins.viewer},
      );

      Future<void> withdrawHelpOffer(String beaconId) => fixture.writer.execute(
        Sql.named('''
DELETE FROM public.beacon_help_offer
WHERE beacon_id = @beacon AND user_id = @viewer
'''),
        parameters: {'beacon': beaconId, 'viewer': _Pins.viewer},
      );

      Future<void> unpin(ConstellationAnchorTarget pinTarget) async {
        final result = await fixture.repository.applyBatch(
          viewerId: _Pins.viewer,
          ops: [
            AnchorApplyOp(
              clientOpId: 'CAOPunpin${pinTarget.id}',
              kind: AnchorOpKind.delete,
              target: pinTarget,
            ),
          ],
        );
        expect(result.results.single.status, AnchorOpStatus.ok);
      }

      setUpAll(() async {
        fixture = _Pins(target);
        await fixture.open();
      });
      tearDownAll(() async => fixture.close());
      setUp(() async => fixture.reset(beaconAuthorId: _someoneElse));

      for (final projection in ConstellationProjection.values) {
        final read = projection.wireValue;

        group('$read reads of a pinned person', () {
          const person = ConstellationAnchorPersonTarget(_Pins.person);

          test(
            'keep someone the viewer blocked at the pin, marked with their name',
            () async {
              await fixture.pin(person);
              await block(_Pins.viewer, _Pins.person);

              final snapshot = await fixture.readSnapshot(projection);
              final projected = snapshot.anchorProjection;

              _expectPinnedAt(projected, person);
              final record = projected.pinnedPeers.singleWhere(
                (peer) => peer.id == _Pins.person,
              );
              expect(record.pinState, 'blockedByMe');
              expect(record.displayName, 'Private profile ${_Pins.person}');
              expect(record.visible, isFalse);
              final wire = _wireRecord(projected, 'pinnedPeers', _Pins.person);
              expect(wire['pinState'], 'blockedByMe');
              expect(wire['displayName'], 'Private profile ${_Pins.person}');
              // The mark is not a way back into the graph.
              expect(
                projected.supportPeers.map((p) => p.id),
                isNot(contains(_Pins.person)),
              );
              expect(
                _edgeEndpoints(projected.supportEdges),
                isNot(contains(_Pins.person)),
              );
              expect(
                _edgeEndpoints(snapshot.edges),
                isNot(contains(_Pins.person)),
              );
            },
          );

          test(
            'hide someone who blocked the viewer, also when the block is mutual, '
            'but not someone only the viewer blocked',
            () async {
              await fixture.writer.execute(
                Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
                parameters: {
                  'id': _mutualBlockPeer,
                  'key': pgTestPublicKey('pinplaceholder', 1),
                },
              );
              const blockedTheViewer = ConstellationAnchorPersonTarget(
                _someoneElse,
              );
              const mutual = ConstellationAnchorPersonTarget(_mutualBlockPeer);
              await fixture.pin(person);
              await fixture.pin(blockedTheViewer);
              await fixture.pin(mutual);
              await block(_Pins.viewer, _Pins.person);
              await block(_someoneElse, _Pins.viewer);
              await block(_Pins.viewer, _mutualBlockPeer);
              await block(_mutualBlockPeer, _Pins.viewer);

              final projected = await fixture.read(projection);

              expect(projected.anchors.map((a) => a.target), [person]);
              expect(projected.pinnedPeers.map((p) => p.id), [_Pins.person]);
              final wire = constellationAnchorProjectionToGqlMap(
                projected,
              ).toString();
              expect(wire, isNot(contains(_someoneElse)));
              expect(wire, isNot(contains(_mutualBlockPeer)));
            },
          );

          test(
            'restore the plain record at the same pin after the viewer unblocks',
            () async {
              final pin = await fixture.pin(person);
              await block(_Pins.viewer, _Pins.person);
              expect(
                (await fixture.read(projection)).pinnedPeers.map(
                  (p) => p.pinState,
                ),
                ['blockedByMe'],
              );

              await unblock(_Pins.viewer, _Pins.person);

              final projected = await fixture.read(projection);
              expect(projected.anchors.single.position, pin.position);
              final record = projected.pinnedPeers.single;
              expect(record.id, _Pins.person);
              expect(record.pinState, isNull);
              expect(record.displayName, 'Private profile ${_Pins.person}');
            },
          );

          test(
            'drop someone the viewer blocked once they are unpinned',
            () async {
              await fixture.pin(person);
              await block(_Pins.viewer, _Pins.person);
              expect(
                (await fixture.read(projection)).anchors.map((a) => a.target),
                [person],
              );

              await unpin(person);

              final projected = await fixture.read(projection);
              expect(projected.anchors, isEmpty);
              expect(projected.pinnedPeers, isEmpty);
            },
          );
        });

        group('$read reads of a pinned Request', () {
          const request = ConstellationAnchorBeaconTarget(_Pins.beacon);

          test(
            'return a content-free noAccess placeholder when the read wall '
            'denies the viewer',
            () async {
              await fixture.pin(request);

              final snapshot = await fixture.readSnapshot(projection);

              _expectSnapshotPlaceholder(snapshot, request, 'noAccess');
            },
          );

          test(
            'return the placeholder alongside the pins the viewer can still read',
            () async {
              const readable = ConstellationAnchorBeaconTarget('Bpinreadable');
              const person = ConstellationAnchorPersonTarget(_Pins.person);
              await insertRequest(readable.id, _someoneElse);
              await offerHelp(readable.id);
              await fixture.pin(request);
              await fixture.pin(readable);
              await fixture.pin(person);

              final projected = await fixture.read(projection);

              expect(
                projected.anchors.map((a) => a.target),
                unorderedEquals([request, readable, person]),
              );
              final records = {
                for (final r in projected.pinnedRequests) r.id: r,
              };
              expect(records.keys, unorderedEquals([request.id, readable.id]));
              expect(records[readable.id]!.pinState, isNull);
              expect(records[readable.id]!.title, _privateTitle);
              expect(records[request.id]!.pinState, 'noAccess');
              expect(records[request.id]!.title, isEmpty);
              expect(records[request.id]!.authorId, isEmpty);
            },
          );

          test(
            'follow read access as it is lost and regained, at the same pin',
            () async {
              await offerHelp(_Pins.beacon);
              final pin = await fixture.pin(request);
              final readable = (await fixture.read(
                projection,
              )).pinnedRequests.single;
              expect(readable.pinState, isNull);
              expect(readable.title, _privateTitle);

              await withdrawHelpOffer(_Pins.beacon);
              final denied = await fixture.read(projection);
              _expectPlaceholder(denied, request, 'noAccess');
              expect(denied.anchors.single.position, pin.position);

              await offerHelp(_Pins.beacon);
              final restored = await fixture.read(projection);
              expect(restored.anchors.single.position, pin.position);
              final record = restored.pinnedRequests.single;
              expect(record.pinState, isNull);
              expect(record.title, _privateTitle);
              expect(record.authorId, _someoneElse);
            },
          );

          test(
            'return a deleted placeholder for a Request its author deleted',
            () async {
              await fixture.pin(request);
              await fixture.writer.execute(
                Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
                parameters: {'id': _Pins.beacon},
              );

              _expectSnapshotPlaceholder(
                await fixture.readSnapshot(projection),
                request,
                'deleted',
              );
            },
          );

          test(
            'return an unpublished placeholder for a Request its author took '
            'back to a draft',
            () async {
              await fixture.pin(request);
              await fixture.writer.execute(
                Sql.named('''
UPDATE public.beacon SET status = 3, published_at = NULL WHERE id = @id
'''),
                parameters: {'id': _Pins.beacon},
              );

              _expectSnapshotPlaceholder(
                await fixture.readSnapshot(projection),
                request,
                'unpublished',
              );
            },
          );

          test(
            'return a content-free blockedByMe placeholder for an author the '
            'viewer blocked, and nothing for an author who blocked the viewer',
            () async {
              const byBlockedAuthor = ConstellationAnchorBeaconTarget(
                'Bpinblockedauthor',
              );
              await insertRequest(byBlockedAuthor.id, _Pins.person);
              await offerHelp(byBlockedAuthor.id);
              await offerHelp(_Pins.beacon);
              await fixture.pin(byBlockedAuthor);
              await fixture.pin(request);
              await block(_Pins.viewer, _Pins.person);
              await block(_someoneElse, _Pins.viewer);

              final snapshot = await fixture.readSnapshot(projection);
              final projected = snapshot.anchorProjection;

              expect(projected.anchors.map((a) => a.target), [byBlockedAuthor]);
              expect(projected.pinnedRequests.map((r) => r.id), [
                byBlockedAuthor.id,
              ]);
              _expectSnapshotPlaceholder(
                snapshot,
                byBlockedAuthor,
                'blockedByMe',
                authorIds: const {_Pins.person, _someoneElse},
              );
              expect(snapshot.requests.map((r) => r.id), isEmpty);
              final wire = constellationAnchorProjectionToGqlMap(
                projected,
              ).toString();
              expect(wire, isNot(contains(_someoneElse)));
              expect(wire, isNot(contains(_Pins.beacon)));
            },
          );

          test(
            'restore the full record at the same pin after the viewer unblocks '
            'the author',
            () async {
              await offerHelp(_Pins.beacon);
              final pin = await fixture.pin(request);
              await block(_Pins.viewer, _someoneElse);
              _expectPlaceholder(
                await fixture.read(projection),
                request,
                'blockedByMe',
              );

              await unblock(_Pins.viewer, _someoneElse);

              final projected = await fixture.read(projection);
              expect(projected.anchors.single.position, pin.position);
              final record = projected.pinnedRequests.single;
              expect(record.pinState, isNull);
              expect(record.title, _privateTitle);
            },
          );

          test('drop the placeholder once the viewer unpins it', () async {
            await fixture.pin(request);
            _expectPlaceholder(
              await fixture.read(projection),
              request,
              'noAccess',
            );

            await unpin(request);

            final projected = await fixture.read(projection);
            expect(projected.anchors, isEmpty);
            expect(projected.pinnedRequests, isEmpty);
          });
        });
      }
      final reads = <String, Future<ConstellationAnchorProjection> Function()>{
        for (final projection in ConstellationProjection.values)
          '${projection.wireValue} snapshot': () => fixture.read(projection),
        for (final prepared in [false, true])
          for (final mutating in [false, true])
            '${prepared ? 'prepared' : 'direct'} reader in a '
                '${mutating ? 'mutating repeatable-read' : 'read-only snapshot'} '
                'transaction': () => fixture.readExtracted(
              prepared: prepared,
              mutating: mutating,
            ),
      };

      for (final MapEntry(key: mode, value: read) in reads.entries) {
        group('$mode pinned Request states', () {
          for (final (status, pinState) in [
            (BeaconStatus.closed, 'closed'),
            (BeaconStatus.reviewOpen, 'wrappingUp'),
            (BeaconStatus.cancelled, 'cancelled'),
            (BeaconStatus.draft, 'unpublished'),
          ]) {
            test(
              'keeps a readable $pinState Request with its content and state',
              () async {
                const request = ConstellationAnchorBeaconTarget(_Pins.beacon);
                final authorId = status == BeaconStatus.draft
                    ? _Pins.viewer
                    : _someoneElse;
                await fixture.writer.execute(
                  Sql.named(
                    'UPDATE public.beacon SET user_id = @author WHERE id = @id',
                  ),
                  parameters: {'author': authorId, 'id': request.id},
                );
                if (authorId != _Pins.viewer) await offerHelp(request.id);
                final pin = await fixture.pin(request);
                await fixture.writer.execute(
                  Sql.named('''
UPDATE public.beacon SET status = @status::smallint,
  published_at = CASE WHEN @status::smallint = 3 THEN NULL ELSE published_at END
WHERE id = @id
'''),
                  parameters: {
                    'status': status.smallintValue,
                    'id': request.id,
                  },
                );
                final readable = await fixture.writer.execute(
                  Sql.named(
                    'SELECT public.beacon_can_read_content(@id, @viewer)',
                  ),
                  parameters: {'id': request.id, 'viewer': _Pins.viewer},
                );
                expect(
                  readable.single.single,
                  isTrue,
                  reason: 'This is a readable state, not a placeholder',
                );

                final projected = await read();

                _expectPinnedAt(projected, request);
                expect(projected.anchors.single.position, pin.position);
                expect(
                  projected.pinnedRequests,
                  hasLength(1),
                  reason:
                      'A readable $pinState pin must retain its full record',
                );
                final record = projected.pinnedRequests.single;
                expect(record.id, request.id);
                expect(record.title, _privateTitle);
                expect(record.authorId, authorId);
                expect(record.status, status.smallintValue);
                expect(record.isMine, authorId == _Pins.viewer);
                expect(record.pinState, pinState);
                final wire = _wireRecord(
                  projected,
                  'pinnedRequests',
                  request.id,
                );
                expect(wire['pinState'], pinState);
                expect(wire['title'], _privateTitle);
                expect(wire['authorId'], authorId);
                expect(wire['status'], status.smallintValue);
              },
            );
          }
        });

        // Snapshot coverage above includes the whole field. Exercise each
        // extracted-reader entry point independently in both caller tx modes.
        if (mode.endsWith('snapshot')) continue;
        group('$mode directional pins and placeholders', () {
          test(
            'marks only viewer-blocked people and hides incoming and mutual blocks',
            () async {
              const unblockedId = 'Ucapinunblocked';
              for (final (index, id) in [
                _mutualBlockPeer,
                unblockedId,
              ].indexed) {
                await fixture.writer.execute(
                  Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
                  parameters: {
                    'id': id,
                    'key': pgTestPublicKey('extractedpins', index + 1),
                  },
                );
              }
              for (final id in [
                _Pins.person,
                _someoneElse,
                _mutualBlockPeer,
                unblockedId,
              ]) {
                await fixture.pin(ConstellationAnchorPersonTarget(id));
              }
              await block(_Pins.viewer, _Pins.person);
              await block(_someoneElse, _Pins.viewer);
              await block(_Pins.viewer, _mutualBlockPeer);
              await block(_mutualBlockPeer, _Pins.viewer);

              final projected = await read();

              expect(
                projected.pinnedPeers.map((p) => p.id),
                unorderedEquals([_Pins.person, unblockedId]),
              );
              expect(
                projected.anchors.map((a) => a.target.id),
                unorderedEquals([_Pins.person, unblockedId]),
              );
              final marked = projected.pinnedPeers.singleWhere(
                (p) => p.id == _Pins.person,
              );
              expect(marked.pinState, 'blockedByMe');
              expect(marked.displayName, 'Private profile ${_Pins.person}');
              expect(marked.visible, isFalse);
              final unblocked = projected.pinnedPeers.singleWhere(
                (p) => p.id == unblockedId,
              );
              expect(unblocked.pinState, isNull);
              expect(unblocked.displayName, unblockedId);
              for (final anchor in projected.anchors) {
                expect(anchor.position, _Pins.position);
              }
              expect(projected.supportEdges, isEmpty);
              final wire = constellationAnchorProjectionToGqlMap(
                projected,
              ).toString();
              expect(wire, isNot(contains(_someoneElse)));
              expect(wire, isNot(contains(_mutualBlockPeer)));
            },
          );

          for (final pinState in [
            'noAccess',
            'deleted',
            'unpublished',
            'blockedByMe',
          ]) {
            test(
              'keeps an inaccessible Request as a content-free $pinState placeholder',
              () async {
                const request = ConstellationAnchorBeaconTarget(_Pins.beacon);
                await fixture.pin(request);
                if (pinState == 'deleted' || pinState == 'unpublished') {
                  await fixture.writer.execute(
                    Sql.named('''
UPDATE public.beacon SET status = @status::smallint,
  published_at = CASE WHEN @status::smallint = 3 THEN NULL ELSE published_at END
WHERE id = @id
'''),
                    parameters: {
                      'status': pinState == 'deleted' ? 2 : 3,
                      'id': request.id,
                    },
                  );
                }
                if (pinState == 'blockedByMe') {
                  await offerHelp(request.id);
                  // The opposite block direction hides a second Request, rather
                  // than confusing it with the viewer's own blocked placeholder.
                  const hidden = ConstellationAnchorBeaconTarget(
                    'Bpinotherblock',
                  );
                  await insertRequest(hidden.id, _Pins.person);
                  await offerHelp(hidden.id);
                  await fixture.pin(hidden);
                  await block(_Pins.viewer, _someoneElse);
                  await block(_Pins.person, _Pins.viewer);
                }

                final projected = await read();

                expect(projected.anchors.map((a) => a.target), [request]);
                _expectPlaceholder(projected, request, pinState);
                expect(projected.pinnedPeers, isEmpty);
                expect(projected.supportPeers, isEmpty);
                expect(projected.supportEdges, isEmpty);
                expect(projected.serverFilteredBeaconIds, isEmpty);
                expect(projected.serverFilteredBeaconCount, 0);
                final wire = constellationAnchorProjectionToGqlMap(
                  projected,
                ).toString();
                expect(wire, isNot(contains(_someoneElse)));
                expect(wire, isNot(contains(_Pins.person)));
                expect(wire, isNot(contains('Bpinotherblock')));
              },
            );
          }
        });
      }
    },
    skip: pgSkip,
  );
}

void _expectPinnedAt(
  ConstellationAnchorProjection projection,
  ConstellationAnchorTarget target,
) {
  final anchor = projection.anchors.where((a) => a.target == target);
  expect(
    anchor,
    hasLength(1),
    reason: 'The pin on ${target.id} must stay on the map',
  );
  expect(anchor.single.position, _Pins.position);
}

Map<String, dynamic> _wireRecord(
  ConstellationAnchorProjection projection,
  String collection,
  String id,
) {
  final wire = constellationAnchorProjectionToGqlMap(projection);
  return (wire[collection] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .singleWhere((record) => record['id'] == id);
}

/// The record says which Request it stands for and why it is empty, nothing
/// else: no title, state details, author or other content, on the entity or on
/// the wire.
void _expectPlaceholder(
  ConstellationAnchorProjection projection,
  ConstellationAnchorBeaconTarget target,
  String pinState,
) {
  _expectPinnedAt(projection, target);
  final matching = projection.pinnedRequests.where((r) => r.id == target.id);
  expect(
    matching,
    hasLength(1),
    reason: 'A pinned Request must not silently vanish from pinnedRequests',
  );
  final record = matching.single;
  expect(record.pinState, pinState);
  expect(record.title, isEmpty);
  expect(record.authorId, isEmpty);
  expect(record.needs, isEmpty);
  expect(record.addressLabel, isNull);
  expect(record.coverThumb, isNull);
  expect(record.isMine, isFalse);

  final wire = _wireRecord(projection, 'pinnedRequests', target.id);
  expect(wire['pinState'], pinState);
  expectContentFreeConstellationRequestWire(wire);
}

Set<String> _edgeEndpoints(Iterable<ConstellationEdgeRecord> edges) => {
  for (final edge in edges) ...[edge.src, edge.dst],
};

/// In these fixtures the inaccessible pin is the only possible source of its
/// author's identity: there is no independent visible relationship to retain.
void _expectSnapshotPlaceholder(
  ConstellationFieldSnapshot snapshot,
  ConstellationAnchorBeaconTarget target,
  String pinState, {
  Set<String> authorIds = const {_someoneElse},
}) {
  final projection = snapshot.anchorProjection;
  expect(snapshot.requests.map((r) => r.id), isNot(contains(target.id)));
  for (final authorId in authorIds) {
    expect(snapshot.peers.map((p) => p.id), isNot(contains(authorId)));
    expect(projection.pinnedPeers.map((p) => p.id), isNot(contains(authorId)));
    expect(projection.supportPeers.map((p) => p.id), isNot(contains(authorId)));
    expect(_edgeEndpoints(snapshot.edges), isNot(contains(authorId)));
    expect(_edgeEndpoints(projection.supportEdges), isNot(contains(authorId)));
    expect(snapshot.directContactIds, isNot(contains(authorId)));
    expect(
      snapshot.memberWebs.map((m) => m.personId),
      isNot(contains(authorId)),
    );
  }
  expect(
    snapshot.memberWebs.map((m) => m.beaconId),
    isNot(contains(target.id)),
  );
  expect(projection.serverFilteredBeaconIds, isEmpty);
  expect(projection.serverFilteredBeaconCount, 0);
  _expectPlaceholder(projection, target, pinState);
}
