@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/utils/id.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_PHANTOM_ANCHOR_TEST_DB',
    defaultNamePrefix: 'tentura_test_phantom_anchor',
  );
  final skipReason = await pgSkipReason(target);

  group('Constellation anchors for people not on Tentura yet', () {
    late Connection writer;
    late _Pins pins;

    setUpAll(() async {
      final session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      addTearDown(() => tearDownDisposablePgWriter(session: session));
    });

    setUp(() async {
      pins = _Pins(writer);
      await pins.seed();
    });

    test(
      'inserting a pin stores a live target and advances its cursor once',
      () async {
        final before = await pins.cursor();
        await pins.insertPhantomPin();

        final pin = (await pins.anchors()).single;
        final after = await pins.cursor();
        pins.expectLivePhantomPin(pin);
        expect(after.revision, before.revision + 1);
        expect(pin['revision'], after.revision);
      },
    );

    test(
      'moving a pin keeps it live and records the new cursor placement',
      () async {
        final id = await pins.insertPhantomPin();
        final before = await pins.cursor();
        await pins.write(
          '''
UPDATE public.constellation_anchor SET x_units = 3.5, y_units = -4.25
WHERE viewer_id = @viewer AND id = @id
''',
          {'viewer': pins.viewer, 'id': id},
        );

        final pin = (await pins.anchors()).single;
        final after = await pins.cursor();
        pins.expectLivePhantomPin(pin);
        expect(pin['id'], id);
        expect([pin['x_units'], pin['y_units']], [3.5, -4.25]);
        expect(after.revision, before.revision + 1);
        expect(pin['revision'], after.revision);
        expect(pin['placed_at'], after.placedAt);
        expect(after.placedAt!.isAfter(before.placedAt!), isTrue);
      },
    );

    test(
      'target deletion keeps account and Request tombstones and removes the placeholder pin',
      () async {
        final siblings = await pins.insertAccountAndRequestPins();
        await pins.sql('DELETE FROM public.beacon WHERE id = @id', {
          'id': pins.beacon,
        });
        await pins.sql('DELETE FROM public."user" WHERE id = @id', {
          'id': pins.person,
        });

        final tombstones = await pins.anchors();
        expect(tombstones, hasLength(2));
        final account = tombstones.singleWhere(
          (row) => row['id'] == siblings.account,
        );
        final request = tombstones.singleWhere(
          (row) => row['id'] == siblings.request,
        );
        expect(account['person_id'], isNull);
        expect(account['target_kind'], 'PERSON');
        expect(account['target_id'], pins.person);
        expect(account['tombstone_at'], isNotNull);
        expect(request['beacon_id'], isNull);
        expect(request['target_kind'], 'BEACON');
        expect(request['target_id'], pins.beacon);
        expect(request['tombstone_at'], isNotNull);

        final id = await pins.insertPhantomPin();
        pins.expectLivePhantomPin(
          (await pins.anchors()).singleWhere((row) => row['id'] == id),
        );
        final before = await pins.cursor();
        final deleted = await pins.write(
          'DELETE FROM public.phantom WHERE id = @id RETURNING id',
          {'id': pins.phantom},
        );

        expect(deleted.single.single, pins.phantom);
        expect(await pins.anchors(), tombstones);
        expect((await pins.cursor()).revision, before.revision + 1);
      },
    );

    test('a placeholder pin cannot also target an account', () async {
      await expectLater(
        pins.insertPhantomPin(person: pins.person),
        _constraintViolation('23514', 'constellation_anchor__target_chk'),
      );
    });

    test('a placeholder pin cannot also target a Request', () async {
      await expectLater(
        pins.insertPhantomPin(beacon: pins.beacon),
        _constraintViolation('23514', 'constellation_anchor__target_chk'),
      );
    });

    test('a pin must reference an existing placeholder', () async {
      await expectLater(
        pins.insertPhantomPin(phantom: generateId('PH')),
        _constraintViolation('23503', 'constellation_anchor_phantom_id_fkey'),
      );
    });

    test(
      'applying a placement creates a live pin, watermark, and operation log',
      () async {
        final id = generateId('CA');
        const opId = 'place-pin';
        final revision = await pins.applyOp(opId, id, x: -6.5, y: 7.25);

        final pin = (await pins.anchors()).single;
        pins.expectLivePhantomPin(pin);
        expect(pin['id'], id);
        expect([pin['x_units'], pin['y_units']], [-6.5, 7.25]);
        expect(pin['coordinate_space_version'], _Pins.coordinateSpaceVersion);
        expect(pin['revision'], revision);
        expect((await pins.cursor()).revision, revision);

        final watermark = await pins.sql(
          '''
SELECT revision FROM public.constellation_anchor_target_watermark
WHERE viewer_id = @viewer AND target_kind = 'PHANTOM' AND target_id = @id
''',
          {'viewer': pins.viewer, 'id': pins.phantom},
        );
        expect(watermark.single.single, revision);
        final log = await pins.sql(
          '''
SELECT revision, result->>'status' FROM public.constellation_anchor_op_log
WHERE viewer_id = @viewer AND client_op_id = @opId
''',
          {'viewer': pins.viewer, 'opId': opId},
        );
        expect(log.single, [revision, 'ok']);
      },
    );

    test(
      'applying a move keeps the pin id and leaves the other pins in place',
      () async {
        await pins.insertAccountAndRequestPins();
        final siblings = await pins.anchors();
        final originalId = await pins.insertPhantomPin();

        await pins.applyOp('move-pin', generateId('CA'), x: 8.5, y: -9.25);

        final rows = await pins.anchors();
        final pin = rows.singleWhere(
          (row) =>
              row['target_kind'] == 'PHANTOM' &&
              row['target_id'] == pins.phantom,
        );
        pins.expectLivePhantomPin(pin);
        expect(pin['id'], originalId);
        expect([pin['x_units'], pin['y_units']], [8.5, -9.25]);
        expect(rows.where((row) => row['id'] != originalId), siblings);
      },
    );

    test(
      'applying an unpin removes the placement at the predicted revision',
      () async {
        await pins.insertPhantomPin();
        pins.expectLivePhantomPin((await pins.anchors()).single);

        final revision = await pins.applyOp('remove-pin', '', delete: true);

        expect(await pins.anchors(), isEmpty);
        expect((await pins.cursor()).revision, revision);
      },
    );
  }, skip: skipReason);
}

Matcher _constraintViolation(String code, String constraint) => throwsA(
  isA<ServerException>()
      .having((error) => error.code, 'SQLSTATE', code)
      .having((error) => error.constraintName, 'constraint', constraint),
);

final class _Pins {
  _Pins(this.writer);

  static const coordinateSpaceVersion = 1;

  final Connection writer;
  final viewer = generateId('U');
  final person = generateId('U');
  final beacon = generateId('B');
  final phantom = generateId('PH');

  Future<Result> sql(String statement, Map<String, Object?> parameters) =>
      writer.execute(Sql.named(statement), parameters: parameters);

  Future<Result> write(String statement, Map<String, Object?> parameters) =>
      writer.executeWithOwnerScopes(
        [viewer],
        Sql.named(statement),
        parameters: parameters,
      );

  Future<void> seed() async {
    for (final id in [viewer, person]) {
      await sql(
        '''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
''',
        {'id': id, 'key': 'pk-$id'},
      );
    }
    await sql(
      '''
INSERT INTO public.beacon (id, user_id, title, description, status, published_at)
VALUES (@id, @viewer, 'Request to pin', 'Description', 0, now())
''',
      {'viewer': viewer, 'id': beacon},
    );
    await write(
      '''
INSERT INTO public.phantom (id, owner_id, display_name)
VALUES (@id, @viewer, 'Anna')
''',
      {'viewer': viewer, 'id': phantom},
    );
    await write(
      '''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES (@viewer)
''',
      {'viewer': viewer},
    );
  }

  Future<({int revision, DateTime? placedAt})> cursor() async {
    final rows = await sql(
      '''
SELECT revision, last_placed_at FROM public.constellation_anchor_cursor
WHERE viewer_id = @viewer
''',
      {'viewer': viewer},
    );
    return (
      revision: rows.single[0]! as int,
      placedAt: rows.single[1] as DateTime?,
    );
  }

  Future<List<Map<String, Object?>>> anchors() async => [
    for (final row in await sql(
      '''
SELECT * FROM public.constellation_anchor WHERE viewer_id = @viewer ORDER BY id
''',
      {'viewer': viewer},
    ))
      row.toColumnMap(),
  ];

  Future<String> insertPhantomPin({
    String? person,
    String? beacon,
    String? phantom,
  }) async {
    final id = generateId('CA');
    await write(
      '''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, beacon_id, phantom_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (@id, @viewer, @person, @beacon, @phantom, 1.25, 2.5, @space, 0, 'epoch')
''',
      {
        'viewer': viewer,
        'id': id,
        'person': person,
        'beacon': beacon,
        'phantom': phantom ?? this.phantom,
        'space': coordinateSpaceVersion,
      },
    );
    return id;
  }

  Future<({String account, String request})>
  insertAccountAndRequestPins() async {
    final account = generateId('CA');
    final request = generateId('CA');
    await write(
      '''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, beacon_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES
  (@account, @viewer, @person, NULL, 1.5, 2.5, @space, 0, 'epoch'),
  (@request, @viewer, NULL, @beacon, -3.5, -4.5, @space, 0, 'epoch')
''',
      {
        'viewer': viewer,
        'account': account,
        'request': request,
        'person': person,
        'beacon': beacon,
        'space': coordinateSpaceVersion,
      },
    );
    return (account: account, request: request);
  }

  void expectLivePhantomPin(Map<String, Object?> pin) {
    expect(pin, containsPair('person_id', null));
    expect(pin, containsPair('beacon_id', null));
    expect(pin, containsPair('phantom_id', phantom));
    expect(pin, containsPair('target_kind', 'PHANTOM'));
    expect(pin, containsPair('target_id', phantom));
    expect(pin, containsPair('tombstone_at', null));
  }

  Future<int> applyOp(
    String opId,
    String anchorId, {
    double x = 0,
    double y = 0,
    bool delete = false,
  }) => withPgOwnerScopes(writer, [viewer], (tx) async {
    final cursor = await tx.execute(
      Sql.named('''
SELECT revision FROM public.constellation_anchor_cursor
WHERE viewer_id = @viewer FOR UPDATE
'''),
      parameters: {'viewer': viewer},
    );
    final revision = (cursor.single.single! as int) + 1;
    await tx.execute(
      Sql.named('''
SELECT public.constellation_anchor_apply_ops(
  @viewer, ARRAY[true], ARRAY[@delete::boolean], ARRAY['PHANTOM'],
  ARRAY[@target::text], ARRAY[@anchor::text],
  ARRAY[@x::double precision], ARRAY[@y::double precision], ARRAY[@space::integer],
  ARRAY[@opId::text], ARRAY[repeat('ab', 32)], ARRAY['{"status":"ok"}'::jsonb],
  ARRAY[@revision::bigint]
)
'''),
      parameters: {
        'viewer': viewer,
        'delete': delete,
        'target': phantom,
        'anchor': anchorId,
        'x': x,
        'y': y,
        'space': delete ? 0 : coordinateSpaceVersion,
        'opId': opId,
        'revision': revision,
      },
    );
    return revision;
  });
}
