@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/constellation_layout_snapshot_repository.dart';
import 'package:tentura_server/domain/entity/constellation_layout_snapshot.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:test/test.dart';

import '../../support/constellation_anchor_batch_fixture.dart';
import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SNAPSHOT_PLACEHOLDER_PINS_TEST_DB',
    defaultNamePrefix: 'tentura_test_layout_placeholder',
  );
  final skipReason = await pgSkipReason(target);

  group('Saved layouts with pins for people not on Tentura yet', () {
    late Connection writer;
    late ConstellationAnchorRepository anchors;
    late ConstellationLayoutSnapshotRepository snapshots;
    late _Layout layout;

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      final db = openDisposablePgDatabase(target);
      addTearDown(
        () => tearDownDisposablePgWriter(session: session, drift: db),
      );
      writer = session.writer;
      anchors = constellationAnchorRepositoryFor(db);
      snapshots = ConstellationLayoutSnapshotRepository(db);
    });

    setUp(() async {
      layout = _Layout(writer, anchors, snapshots);
      await layout.seedAccounts();
    });

    test(
      'a mixed layout retains its saved pins after a link and restores the linked account',
      () async {
        final placeholder = await layout.createPlaceholder();
        final request = await layout.createRequest();
        await layout.pin(placeholder, 12, -4);
        await layout.pin(layout.person, -3, 7);
        await layout.pin(request, 2, 9);

        final saved = await layout.save();
        final expected = [
          _savedPin(placeholder, 12, -4),
          _savedPin(layout.person, -3, 7),
          _savedPin(request, 2, 9),
        ];
        expect(saved.anchorCount, 3);
        expect(saved.anchors.map(_placement), unorderedEquals(expected));
        await layout.expectSavedPins(saved.id, expected);

        await layout.markMerged(placeholder, into: layout.joined);
        await layout.expectSavedPins(saved.id, expected);
        expect(
          await layout.livePins(),
          unorderedEquals([
            _livePin(placeholder, 12, -4),
            _livePin(layout.person, -3, 7),
            _livePin(request, 2, 9),
          ]),
        );

        await layout.restore(saved.id);

        await layout.expectSavedPins(saved.id, expected);
        expect(
          await layout.livePins(),
          unorderedEquals([
            _livePin(layout.joined, 12, -4),
            _livePin(layout.person, -3, 7),
            _livePin(request, 2, 9),
          ]),
        );
      },
    );

    test(
      'restore moves or recreates a saved active pin and removes pins added later',
      () async {
        final savedPin = await layout.createPlaceholder();
        final laterPin = await layout.createPlaceholder();
        await layout.pin(savedPin, 12, -4);
        final saved = await layout.save();
        await layout.pin(savedPin, 0, 0);
        await layout.pin(laterPin, 3, 4);

        await layout.restore(saved.id);

        final expected = [_livePin(savedPin, 12, -4)];
        expect(await layout.livePins(), expected);

        await layout.unpin(savedPin);
        await layout.restore(saved.id);

        expect(await layout.livePins(), expected);
      },
    );

    test('restore moves an existing linked account to the saved pin', () async {
      final placeholder = await layout.createPlaceholder();
      await layout.pin(placeholder, 12, -4);
      final saved = await layout.save();
      await layout.unpin(placeholder);
      await layout.markMerged(placeholder, into: layout.joined);
      await layout.pin(layout.joined, 5, 5);

      await layout.restore(saved.id);

      expect(await layout.livePins(), [_livePin(layout.joined, 12, -4)]);
    });

    test(
      'restore skips orphaned and deleted placeholders and restores the saved account pin',
      () async {
        final orphaned = await layout.createPlaceholder();
        final deleted = await layout.createPlaceholder();
        await layout.pin(orphaned, 12, -4);
        await layout.pin(deleted, -5, 8);
        await layout.pin(layout.person, 2, 9);
        final saved = await layout.save();
        await layout.markMerged(orphaned);
        await layout.deletePlaceholder(deleted);
        await layout.pin(layout.person, 0, 0);

        await layout.restore(saved.id);

        expect(await layout.livePins(), [_livePin(layout.person, 2, 9)]);
      },
    );

    for (final first in [
      ConstellationAnchorTargetKind.person,
      ConstellationAnchorTargetKind.phantom,
    ]) {
      final firstLabel = first == ConstellationAnchorTargetKind.person
          ? 'account'
          : 'placeholder';
      test(
        'the placeholder position wins when the $firstLabel is listed first',
        () async {
          final placeholder = await layout.createPlaceholder();
          await layout.pin(layout.joined, 10, 10);
          await layout.pin(placeholder, 25, 25);
          final saved = await layout.save();
          await layout.orderSavedPins(saved.id, first);
          await layout.unpin(placeholder);
          await layout.markMerged(placeholder, into: layout.joined);
          await layout.pin(layout.joined, 5, 5);

          await layout.restore(saved.id);

          expect(await layout.livePins(), [_livePin(layout.joined, 25, 25)]);
        },
      );
    }

    test(
      'restoring a favourite keeps active pins, moves linked pins to accounts, and drops unavailable pins',
      () async {
        final active = await layout.createPlaceholder();
        final linked = await layout.createPlaceholder();
        final orphaned = await layout.createPlaceholder();
        final deleted = await layout.createPlaceholder();
        await layout.pin(active, 12, -4);
        await layout.pin(linked, -8, 9);
        await layout.pin(orphaned, 2, 3);
        await layout.pin(deleted, 4, 5);
        final saved = await layout.save(
          kind: ConstellationLayoutSnapshotKind.favourite,
        );
        await layout.unpin(active);
        await layout.markMerged(linked, into: layout.joined);
        await layout.markMerged(orphaned);
        await layout.deletePlaceholder(deleted);

        await snapshots.restoreFavourite(
          viewerId: layout.viewer,
          snapshotId: saved.id,
          clientOpId: generateId('OP'),
        );

        expect(
          await layout.livePins(),
          unorderedEquals([
            _livePin(active, 12, -4),
            _livePin(layout.joined, -8, 9),
          ]),
        );
      },
    );
  }, skip: skipReason);
}

const _space = kConstellationCoordinateSpaceVersionV1;

typedef _SavedPin = (
  ConstellationAnchorTargetKind,
  String,
  double,
  double,
  int,
);

_SavedPin _savedPin(ConstellationAnchorTarget target, double x, double y) =>
    (target.kind, target.id, x, y, _space);

_SavedPin _placement(ConstellationLayoutSnapshotAnchor pin) =>
    (pin.targetKind, pin.targetId, pin.x, pin.y, pin.coordinateSpaceVersion);

List<Object?> _livePin(ConstellationAnchorTarget target, double x, double y) =>
    [
      target.kind.wireValue,
      if (target is ConstellationAnchorPersonTarget) target.id else null,
      if (target is ConstellationAnchorBeaconTarget) target.id else null,
      if (target is ConstellationAnchorPhantomTarget) target.id else null,
      x,
      y,
      _space,
    ];

final class _Layout {
  _Layout(this.writer, this.anchors, this.snapshots);

  final Connection writer;
  final ConstellationAnchorRepository anchors;
  final ConstellationLayoutSnapshotRepository snapshots;
  final viewer = generateId('U');
  final person = ConstellationAnchorTarget.person(generateId('U'));
  final joined = ConstellationAnchorTarget.person(generateId('U'));

  Future<void> seedAccounts() async {
    for (final id in [viewer, person.id, joined.id]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
        parameters: {'id': id, 'key': 'pk-$id'},
      );
    }
  }

  Future<ConstellationAnchorTarget> createRequest() async {
    final id = generateId('B');
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @viewer, 'Request to pin', 'Description', 0, now())
'''),
      parameters: {'viewer': viewer, 'id': id},
    );
    return ConstellationAnchorTarget.beacon(id);
  }

  Future<ConstellationAnchorPhantomTarget> createPlaceholder() async {
    final id = generateId('PH');
    await writer.executeWithOwnerScopes(
      [viewer],
      Sql.named('''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @viewer, 'Anna')
'''),
      parameters: {'viewer': viewer, 'id': id},
    );
    return ConstellationAnchorPhantomTarget(id);
  }

  // A missing account leaves the placeholder orphaned. Set the state directly
  // while the account linking flow is absent.
  Future<void> markMerged(
    ConstellationAnchorPhantomTarget placeholder, {
    ConstellationAnchorTarget? into,
  }) async {
    await writer.executeWithOwnerScopes(
      [viewer],
      Sql.named('''
UPDATE public.phantom
SET merged_at = now(), merged_user_id = @account, merge_origin = 3
WHERE id = @id AND owner_id = @viewer
'''),
      parameters: {'viewer': viewer, 'id': placeholder.id, 'account': into?.id},
    );
  }

  Future<void> deletePlaceholder(
    ConstellationAnchorPhantomTarget placeholder,
  ) async {
    await writer.executeWithOwnerScopes(
      [viewer],
      Sql.named(
        'DELETE FROM public.phantom WHERE id = @id AND owner_id = @viewer',
      ),
      parameters: {'viewer': viewer, 'id': placeholder.id},
    );
  }

  Future<void> pin(ConstellationAnchorTarget target, double x, double y) async {
    await anchors.applyAnchorUpsert(
      viewerId: viewer,
      context: '',
      target: target,
      position: ConstellationAnchorPosition(
        xUnits: x,
        yUnits: y,
        coordinateSpaceVersion: _space,
      ),
    );
  }

  Future<void> unpin(ConstellationAnchorTarget target) async {
    await anchors.applyAnchorDelete(viewerId: viewer, target: target);
  }

  Future<ConstellationLayoutSnapshot> save({
    ConstellationLayoutSnapshotKind kind =
        ConstellationLayoutSnapshotKind.history,
  }) => snapshots.save(
    viewerId: viewer,
    kind: kind,
    reason: ConstellationLayoutSnapshotReason.manual,
    clientOpId: generateId('OP'),
  );

  Future<void> restore(String id) async {
    await snapshots.restore(
      viewerId: viewer,
      snapshotId: id,
      clientOpId: generateId('OP'),
    );
  }

  Future<void> expectSavedPins(String id, List<_SavedPin> expected) async {
    final listed = (await snapshots.list(
      viewer,
    )).singleWhere((s) => s.id == id);
    expect(listed.anchorCount, expected.length);
    expect(listed.anchors.map(_placement), unorderedEquals(expected));
  }

  Future<void> orderSavedPins(
    String id,
    ConstellationAnchorTargetKind first,
  ) async {
    // Capture has no ordering contract. Exercise both persisted array orders.
    await writer.executeWithOwnerScopes(
      [viewer],
      Sql.named('''
UPDATE public.constellation_layout_snapshot AS snapshot
SET anchors = (
  SELECT jsonb_agg(entry ORDER BY (entry ->> 'targetKind' = @first) DESC)
  FROM jsonb_array_elements(snapshot.anchors) AS pins(entry)
)
WHERE id = @id AND viewer_id = @viewer
'''),
      parameters: {'viewer': viewer, 'id': id, 'first': first.name},
    );
    final listed = (await snapshots.list(viewer)).single;
    expect(listed.anchors.map((pin) => pin.targetKind), [
      first,
      if (first == ConstellationAnchorTargetKind.phantom)
        ConstellationAnchorTargetKind.person
      else
        ConstellationAnchorTargetKind.phantom,
    ]);
  }

  Future<List<List<Object?>>> livePins() async {
    final rows = await writer.execute(
      Sql.named('''
SELECT target_kind, person_id, beacon_id, phantom_id,
       x_units, y_units, coordinate_space_version
FROM public.constellation_anchor
WHERE viewer_id = @viewer AND tombstone_at IS NULL
'''),
      parameters: {'viewer': viewer},
    );
    return rows.map((row) => row.toList()).toList();
  }
}
